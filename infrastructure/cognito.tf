# =============================================================================
# DocuMagic – Amazon Cognito
# User Pool | Identity Pool | App Client | Domain | Authorizer
# =============================================================================

# ---------------------------------------------------------------------------
# User Pool
# ---------------------------------------------------------------------------
resource "aws_cognito_user_pool" "documagic" {
  name = "${local.name_prefix}-user-pool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 7
  }

  mfa_configuration = "OPTIONAL"

  software_token_mfa_configuration {
    enabled = true
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  schema {
    name                = "email"
    attribute_data_type = "String"
    mutable             = true
    required            = true
    string_attribute_constraints {
      min_length = 5
      max_length = 254
    }
  }

  schema {
    name                = "name"
    attribute_data_type = "String"
    mutable             = true
    required            = true
    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }

  schema {
    name                = "organization"
    attribute_data_type = "String"
    mutable             = true
    required            = false
    string_attribute_constraints {
      min_length = 0
      max_length = 256
    }
  }

  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  verification_message_template {
    default_email_option  = "CONFIRM_WITH_CODE"
    email_subject         = "DocuMagic – Verify your account"
    email_message         = "Your DocuMagic verification code is {####}"
    email_subject_by_link = "DocuMagic – Verify your email"
    email_message_by_link = "Please click the following link to verify your email: {##Verify Email##}"
  }

  lambda_config {
    pre_sign_up         = null
    post_confirmation   = null
    pre_token_generation = null
  }

  tags = { Name = "${local.name_prefix}-user-pool" }
}

# ---------------------------------------------------------------------------
# User Pool Domain
# ---------------------------------------------------------------------------
resource "aws_cognito_user_pool_domain" "documagic" {
  domain       = "${lower(local.name_prefix)}-auth-${data.aws_caller_identity.current.account_id}"
  user_pool_id = aws_cognito_user_pool.documagic.id
}

# ---------------------------------------------------------------------------
# App Client (used by Amplify frontend)
# ---------------------------------------------------------------------------
resource "aws_cognito_user_pool_client" "documagic" {
  name         = "${local.name_prefix}-app-client"
  user_pool_id = aws_cognito_user_pool.documagic.id

  generate_secret = false

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes = [
    "openid",
    "email",
    "profile",
    "aws.cognito.signin.user.admin"
  ]

  callback_urls = var.cognito_callback_urls
  logout_urls   = var.cognito_logout_urls

  supported_identity_providers = ["COGNITO"]

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_PASSWORD_AUTH"
  ]

  access_token_validity  = 1    # hours
  id_token_validity      = 1    # hours
  refresh_token_validity = 30   # days

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  enable_token_revocation               = true
  prevent_user_existence_errors         = "ENABLED"
  read_attributes                       = ["email", "name", "custom:organization"]
  write_attributes                      = ["email", "name", "custom:organization"]
}

# ---------------------------------------------------------------------------
# Machine-to-machine client (Lambda / backend services)
# ---------------------------------------------------------------------------
resource "aws_cognito_user_pool_client" "m2m" {
  name         = "${local.name_prefix}-m2m-client"
  user_pool_id = aws_cognito_user_pool.documagic.id

  generate_secret = true

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["client_credentials"]
  allowed_oauth_scopes                 = ["${aws_cognito_resource_server.documagic.identifier}/read", "${aws_cognito_resource_server.documagic.identifier}/write"]

  supported_identity_providers = ["COGNITO"]

  explicit_auth_flows = ["ALLOW_REFRESH_TOKEN_AUTH"]

  access_token_validity  = 1
  refresh_token_validity = 1

  token_validity_units {
    access_token  = "hours"
    refresh_token = "days"
  }

  enable_token_revocation       = true
  prevent_user_existence_errors = "ENABLED"
}

# ---------------------------------------------------------------------------
# Resource Server (for M2M scopes)
# ---------------------------------------------------------------------------
resource "aws_cognito_resource_server" "documagic" {
  identifier   = "https://api.documagic.example.com"
  name         = "${local.name_prefix}-resource-server"
  user_pool_id = aws_cognito_user_pool.documagic.id

  scope {
    scope_name        = "read"
    scope_description = "Read access to DocuMagic APIs"
  }

  scope {
    scope_name        = "write"
    scope_description = "Write access to DocuMagic APIs"
  }
}

# ---------------------------------------------------------------------------
# Identity Pool – grants AWS credentials to authenticated users
# ---------------------------------------------------------------------------
resource "aws_cognito_identity_pool" "documagic" {
  identity_pool_name               = "${replace(local.name_prefix, "-", "_")}_identity_pool"
  allow_unauthenticated_identities = false
  allow_classic_flow               = false

  cognito_identity_providers {
    client_id               = aws_cognito_user_pool_client.documagic.id
    provider_name           = aws_cognito_user_pool.documagic.endpoint
    server_side_token_check = true
  }

  tags = { Name = "${local.name_prefix}-identity-pool" }
}

# ---------------------------------------------------------------------------
# Identity Pool Role Attachment
# ---------------------------------------------------------------------------
resource "aws_iam_role" "cognito_authenticated" {
  name = "${local.name_prefix}-cognito-auth-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = "cognito-identity.amazonaws.com"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "cognito-identity.amazonaws.com:aud" = aws_cognito_identity_pool.documagic.id
        }
        "ForAnyValue:StringLike" = {
          "cognito-identity.amazonaws.com:amr" = "authenticated"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "cognito_authenticated" {
  name = "${local.name_prefix}-cognito-auth-policy"
  role = aws_iam_role.cognito_authenticated.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.raw_ingest.arn}/uploads/$${cognito-identity.amazonaws.com:sub}/*"
      },
      {
        Effect = "Allow"
        Action = ["execute-api:Invoke"]
        Resource = "arn:aws:execute-api:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.documagic.id}/*"
      }
    ]
  })
}

resource "aws_cognito_identity_pool_roles_attachment" "documagic" {
  identity_pool_id = aws_cognito_identity_pool.documagic.id

  roles = {
    "authenticated" = aws_iam_role.cognito_authenticated.arn
  }
}

# ---------------------------------------------------------------------------
# User Groups
# ---------------------------------------------------------------------------
resource "aws_cognito_user_group" "admins" {
  name         = "Admins"
  user_pool_id = aws_cognito_user_pool.documagic.id
  description  = "DocuMagic administrators"
  precedence   = 1
}

resource "aws_cognito_user_group" "users" {
  name         = "Users"
  user_pool_id = aws_cognito_user_pool.documagic.id
  description  = "Standard DocuMagic users"
  precedence   = 10
}
