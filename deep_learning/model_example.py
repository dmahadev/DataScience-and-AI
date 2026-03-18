"""
Deep Learning Model Example
============================
Demonstrates how to:
  1. Build and add layers to a neural network model using Keras (TensorFlow)
  2. Compile and train the model
  3. Get predictions / model output

Requirements:
    pip install tensorflow numpy
"""

import numpy as np
import tensorflow as tf
from tensorflow import keras
from tensorflow.keras import layers


# ---------------------------------------------------------------------------
# 1. Generate synthetic data
# ---------------------------------------------------------------------------
def generate_data(num_samples: int = 1000, num_features: int = 20, num_classes: int = 3):
    """Create a random classification dataset for demonstration."""
    np.random.seed(42)
    X = np.random.randn(num_samples, num_features).astype(np.float32)
    y = np.random.randint(0, num_classes, size=num_samples)
    # One-hot encode labels
    y_onehot = keras.utils.to_categorical(y, num_classes=num_classes)
    return X, y_onehot, num_classes


# ---------------------------------------------------------------------------
# 2. Build the model
# ---------------------------------------------------------------------------
def build_model(input_dim: int, num_classes: int) -> keras.Model:
    """
    Build a simple fully-connected (Dense) neural network.

    Architecture:
        Input  -> Dense(64, relu) -> Dense(32, relu) -> Dense(num_classes, softmax)
    """
    model = keras.Sequential(
        [
            keras.Input(shape=(input_dim,), name="input_layer"),
            layers.Dense(64, activation="relu", name="hidden_layer_1"),
            layers.Dense(32, activation="relu", name="hidden_layer_2"),
            layers.Dense(num_classes, activation="softmax", name="output_layer"),
        ],
        name="deep_learning_demo",
    )
    return model


# ---------------------------------------------------------------------------
# 3. Compile the model
# ---------------------------------------------------------------------------
def compile_model(model: keras.Model) -> keras.Model:
    """Attach optimizer, loss function, and evaluation metric to the model."""
    model.compile(
        optimizer="adam",
        loss="categorical_crossentropy",
        metrics=["accuracy"],
    )
    return model


# ---------------------------------------------------------------------------
# 4. Train the model
# ---------------------------------------------------------------------------
def train_model(
    model: keras.Model,
    X_train: np.ndarray,
    y_train: np.ndarray,
    epochs: int = 10,
    batch_size: int = 32,
    validation_split: float = 0.2,
) -> keras.callbacks.History:
    """Fit the model to the training data and return the training history."""
    history = model.fit(
        X_train,
        y_train,
        epochs=epochs,
        batch_size=batch_size,
        validation_split=validation_split,
        verbose=1,
    )
    return history


# ---------------------------------------------------------------------------
# 5. Get model output (predictions)
# ---------------------------------------------------------------------------
def get_predictions(model: keras.Model, X: np.ndarray) -> np.ndarray:
    """
    Run the model on input data and return:
      - raw_output  : probability distribution over classes (shape: [n, num_classes])
      - class_labels: predicted class index for each sample  (shape: [n])
    """
    raw_output = model.predict(X, verbose=0)       # softmax probabilities
    class_labels = np.argmax(raw_output, axis=1)   # most likely class
    return raw_output, class_labels


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    print("=" * 60)
    print("Deep Learning Model Demo")
    print("=" * 60)

    # --- Data ---
    num_features = 20
    X, y, num_classes = generate_data(num_samples=1000, num_features=num_features)
    print(f"\nDataset  : {X.shape[0]} samples, {num_features} features, {num_classes} classes")

    # Split into train / test (80 / 20)
    split = int(0.8 * len(X))
    X_train, X_test = X[:split], X[split:]
    y_train, y_test = y[:split], y[split:]

    # --- Model ---
    model = build_model(input_dim=num_features, num_classes=num_classes)
    model = compile_model(model)

    print("\nModel Summary:")
    model.summary()

    # --- Training ---
    print("\nTraining the model …")
    history = train_model(model, X_train, y_train, epochs=10, batch_size=32)

    # --- Evaluate ---
    print("\nEvaluating on test set …")
    test_loss, test_accuracy = model.evaluate(X_test, y_test, verbose=0)
    print(f"Test Loss     : {test_loss:.4f}")
    print(f"Test Accuracy : {test_accuracy:.4f}")

    # --- Get output ---
    print("\nGetting model output (predictions) for first 5 test samples …")
    sample = X_test[:5]
    raw_output, predicted_classes = get_predictions(model, sample)

    print("\nRaw softmax output (probability per class):")
    for i, probs in enumerate(raw_output):
        formatted = "  ".join(f"class {j}: {p:.3f}" for j, p in enumerate(probs))
        print(f"  Sample {i + 1}: {formatted}")

    print("\nPredicted class labels:", predicted_classes)
    print("True  class labels    :", np.argmax(y_test[:5], axis=1))

    print("\nDone.")


if __name__ == "__main__":
    main()
