Of course. Here are the detailed technical specifications for the third of the five essential missing component layers: the **Data Management Layer**.

This document provides the complete design for the components responsible for ingesting, representing, and manipulating the datasets used for evaluation and optimization. A robust and standardized data layer is the bedrock of a scientific framework, ensuring that all experiments are conducted on consistent, well-defined data.

---

### **`10_SPEC_DATA_MANAGEMENT_LAYER.md`**

# Technical Specification: The Data Management Layer

## 1. Vision and Guiding Principles

The Data Management Layer provides the foundational data structures and utilities for all evaluation and optimization workflows in `dspex`. It ensures that data is handled in a consistent, reproducible, and efficient manner.

*   **Immutability:** Data structures like `Example` and `Dataset` are immutable, promoting functional purity and preventing side effects in parallel evaluations.
*   **Standardization:** Provides a canonical, Elixir-native representation for datasets, abstracting away the specifics of the original file formats.
*   **Reproducibility:** All data splitting and sampling operations are deterministic when provided with a seed, a critical requirement for the `ExperimentJournal`.
*   **Efficiency:** Loaders and samplers are designed to handle large datasets efficiently, including support for streaming where applicable.
*   **Interoperability:** The `DSPex.Example` struct is designed for seamless serialization across the gRPC bridge to be compatible with Python's `dspy.Example`.

## 2. Core Components

This layer consists of two primary components:

1.  **`DSPex.Example`**: The core data structure representing a single, atomic data point for training, evaluation, or demonstration.
2.  **`DSPex.Dataset`**: A module that provides a comprehensive suite of functions for loading, splitting, sampling, and manipulating collections of `Example` structs.

---

## 3. `DSPex.Example`: The Canonical Data Point

The `DSPex.Example` is an immutable struct that represents a single record. It is a direct Elixir counterpart to `dspy.Example` and is the fundamental unit of data passed throughout the system.

### 3.1. Purpose

*   To provide a consistent, structured representation for all data.
*   To clearly delineate between input fields (used for prediction) and label fields (used for evaluation).
*   To be easily serializable for transport over the gRPC bridge.

### 3.2. Definition (`defstruct`)

```elixir
defmodule DSPex.Example do
  @moduledoc """
  An immutable struct representing a single data point.
  It stores data as a map and maintains a set of keys designated as inputs.
  """
  @enforce_keys [:fields]
  defstruct [
    fields: %{},          # The core map holding all data, e.g., %{"question" => "...", "answer" => "..."}
    input_keys: MapSet.new(), # A set of keys from `fields` to be treated as inputs
    metadata: %{}          # Optional metadata, e.g., source file, original ID
  ]
end
```

### 3.3. Public API (`@spec`)

The `DSPex.Example` module provides a rich, functional API for manipulating examples without mutation.

```elixir
@doc "Creates a new example from a map."
@spec new(map(), keyword()) :: %__MODULE__{}
def new(fields, opts \\ [])

@doc """
Designates which fields should be treated as inputs for the LM.
Returns a new `Example` with the updated input keys.
"""
@spec with_inputs(%__MODULE__{}, list(String.t() | atom())) :: %__MODULE__{}
def with_inputs(example, keys)

@doc "Returns a map containing only the input fields and their values."
@spec inputs(%__MODULE__{}) :: map()
def inputs(example)

@doc "Returns a map containing only the label (non-input) fields and their values."
@spec labels(%__MODULE__{}) :: map()
def labels(example)

@doc "Returns the value of a specific field."
@spec get(%__MODULE__{}, String.t() | atom()) :: any()
def get(example, key)

@doc "Adds or updates a field, returning a new `Example`."
@spec put(%__MODULE__{}, String.t() | atom(), any()) :: %__MODULE__{}
def put(example, key, value)

@doc "Converts the example to a simple map, ready for serialization."
@spec to_map(%__MODULE__{}) :: map()
def to_map(example)
```

### 3.4. Serialization

When a `DSPex.Example` needs to be sent to a Python worker (e.g., as a few-shot demo), the `TrialRunner` will call `to_map/1`, which will be serialized to JSON. The Python side will then reconstruct it into a `dspy.Example` object. This ensures perfect compatibility.

---

## 4. `DSPex.Dataset`: The Data Manipulation Toolkit

This is a stateless module that provides a comprehensive set of functions for data management. It operates on lists of `DSPex.Example` structs.

### 4.1. Purpose

*   To provide standardized, reproducible methods for common dataset operations.
*   To abstract the details of data loading from various file formats.
*   To be the primary tool used by the `ExperimentJournal` and `SIMBA-C` for data preparation.

### 4.2. Public API (`@spec`)

#### **Data Loading**

```elixir
@doc """
Loads a dataset from a file, returning a list of `DSPex.Example` structs.

Supported formats are determined by file extension: `.jsonl`, `.csv`.
"""
@spec load(path :: String.t(), opts :: keyword()) :: {:ok, list(%DSPex.Example{})} | {:error, term()}
def load(path, opts \\ [])```

#### **Data Splitting (for creating train/val/test sets)**

```elixir
@doc """
Splits a dataset into multiple partitions based on ratios.

Returns a map of `%{split_name => list(%DSPex.Example{})}`.
The operation is deterministic if a `:seed` is provided.
"""
@spec split(list(%DSPex.Example{}), map(), keyword()) :: {:ok, map()} | {:error, term()}
def split(dataset, splits, opts \\ [])

# Example:
# DSPex.Dataset.split(my_data, %{train: 0.7, val: 0.15, test: 0.15}, seed: 42)
```

#### **Data Sampling (for creating mini-batches)**

```elixir
@doc """
Randomly samples a specified number of examples from a dataset.

Deterministic if a `:seed` is provided.
"""
@spec sample(list(%DSPex.Example{}), integer(), keyword()) :: list(%DSPex.Example{})
def sample(dataset, n, opts \\ [])

@doc """
Creates a mini-batch of a given size from the dataset.
"""
@spec minibatch(list(%DSPex.Example{}), integer(), keyword()) :: list(%DSPex.Example{})
def minibatch(dataset, batch_size, opts \\ [])
```

#### **Cross-Validation Support**

```elixir
@doc """
Generates k-folds for cross-validation.

Returns a list of tuples, where each tuple is `{train_fold, test_fold}`.
Deterministic if a `:seed` is provided.
"""
@spec k_folds(list(%DSPex.Example{}), integer(), keyword()) :: {:ok, list({list(), list()})}
def k_folds(dataset, k, opts \\ [])
```

### 4.3. Internal Logic - `load/2` Workflow

1.  **Detect Format:** The function inspects the file extension of the `path`.
2.  **Select Parser:** It dispatches to a format-specific private function (e.g., `parse_jsonl/1`, `parse_csv/1`).
3.  **Streaming Parse:** For performance with large files, the parsers should use Elixir `Stream`s to process the file line-by-line, avoiding loading the entire file into memory.
    *   `File.stream!/1`
    *   `Stream.map(&Jason.decode!/1)` (for JSONL)
    *   `CSV.parse_stream/1` (with a library like `NimbleCSV`)
4.  **Create Examples:** Each line/row is converted into a `DSPex.Example.new/1` call.
5.  **Return List:** `Stream.to_list/1` is called at the end to return the complete list of examples.

### 4.4. Internal Logic - `split/3` and `sample/3`

*   **Reproducibility is Key:** Both functions **must** accept a `:seed` option.
*   When a seed is provided, a new random number generator should be initialized with it (`:rand.seed(:exsplus, {seed, seed, seed})`) at the beginning of the function. This ensures that the same seed will always produce the same split or sample.
*   The default implementation should use Elixir's built-in `Enum.shuffle/1` and `Enum.take/2` after seeding the default RNG.

## 5. Integration with Other Components

*   **`ExperimentJournal`:**
    *   Will use `Dataset.load/2` to load the benchmark datasets specified in an `ExperimentalDesign`.
    *   Will use `Dataset.split/3` to create the training, validation, and testing sets for an experiment, passing a deterministic seed to ensure reproducibility.

*   **`SIMBA-C` Optimizer:**
    *   Will use `Dataset.minibatch/3` at each step of its optimization loop to get a new, random sample of the `trainset` for evaluating candidate programs. A new seed can be used for each step to ensure varied batches.

*   **`TrialRunner`:**
    *   Will receive `DSPex.Example` structs as part of its `TrialSpec`. It will serialize these examples into maps (`to_map/1`) before sending them over the gRPC bridge, for example, to be used as few-shot demonstrations in the Python `dspy.Module`.

## 6. Conclusion

The Data Management Layer provides the clean, robust, and reproducible data handling that is essential for a scientific evaluation platform. By standardizing on an immutable `DSPex.Example` struct and providing a comprehensive toolkit in the `DSPex.Dataset` module, we equip all other components of the framework with the tools they need to perform their functions reliably.

This layer successfully abstracts away the messiness of file I/O and data manipulation, allowing the higher-level components like the `ExperimentJournal` and `SIMBA-C` to focus on their core logic of scientific inquiry and optimization.
