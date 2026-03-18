# Deep Learning — Add a Model and Get Output

This directory shows how to **build a deep learning model** with Keras (TensorFlow),
**train it**, and **retrieve its output (predictions)**.

---

## Concepts Covered

| Step | What it does |
|------|-------------|
| **Build the model** | Stack layers (`Dense`, `Activation`, etc.) using `keras.Sequential` |
| **Compile the model** | Choose optimizer, loss function, and metrics |
| **Train the model** | Call `model.fit()` with training data |
| **Get the output** | Call `model.predict()` to obtain probabilities and class labels |

---

## File

| File | Description |
|------|-------------|
| `model_example.py` | End-to-end script: generate data → build model → train → predict |

---

## Quick Start

### 1. Install dependencies

```bash
pip install tensorflow numpy
```

### 2. Run the example

```bash
python deep_learning/model_example.py
```

### Expected output (abbreviated)

```
============================================================
Deep Learning Model Demo
============================================================

Dataset  : 1000 samples, 20 features, 3 classes

Model Summary:
Model: "deep_learning_demo"
_________________________________________________________________
 Layer (type)               Output Shape          Param #
=================================================================
 hidden_layer_1 (Dense)     (None, 64)            1344
 hidden_layer_2 (Dense)     (None, 32)            2080
 output_layer (Dense)       (None, 3)             99
=================================================================

Training the model …
Epoch 1/10  ...
...
Epoch 10/10 ...

Evaluating on test set …
Test Loss     : 1.0980
Test Accuracy : 0.3700

Getting model output (predictions) for first 5 test samples …

Raw softmax output (probability per class):
  Sample 1: class 0: 0.312  class 1: 0.358  class 2: 0.330
  ...

Predicted class labels: [1 2 0 1 0]
True  class labels    : [2 1 0 0 2]
```

---

## Key Code Patterns

### Adding layers to a model

```python
from tensorflow import keras
from tensorflow.keras import layers

model = keras.Sequential([
    keras.Input(shape=(input_dim,)),
    layers.Dense(64, activation="relu"),   # hidden layer 1
    layers.Dense(32, activation="relu"),   # hidden layer 2
    layers.Dense(num_classes, activation="softmax"),  # output layer
])
```

### Compiling and training

```python
model.compile(optimizer="adam", loss="categorical_crossentropy", metrics=["accuracy"])
model.fit(X_train, y_train, epochs=10, batch_size=32, validation_split=0.2)
```

### Getting output

```python
# Raw probabilities (shape: [n_samples, num_classes])
raw_output = model.predict(X_new)

# Predicted class index for each sample
predicted_classes = raw_output.argmax(axis=1)
```

---

## Further Reading

- [Keras Sequential model guide](https://keras.io/guides/sequential_model/)
- [TensorFlow tutorials](https://www.tensorflow.org/tutorials)
