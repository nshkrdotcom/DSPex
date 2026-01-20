# RLM Data Extraction Experiment (NYC 311)

This experiment uses a real government dataset (NYC 311 service requests) and asks
concrete, computable questions over 50,000 structured records. The context becomes
massive once serialized, which pushes direct LLM prompting into truncation and
approximation. RLM avoids that by storing the dataset as a Python variable and
letting the model write code to compute exact answers.

## What the Experiment Does

1. Downloads and caches 50,000 NYC 311 records.
2. Builds a document-like context representation of all rows.
3. Runs 6 structured queries with RLM (code execution).
4. Runs the same queries with a direct LLM on a truncated context.
5. Compares accuracy against programmatic ground truth.

## Dataset

**NYC 311 Service Requests**
- Source: https://data.cityofnewyork.us/Social-Services/311-Service-Requests-from-2010-to-Present/erm2-nwe9
- Format: CSV via Socrata API
- Size: 50,000 rows (large enough to exceed typical LLM context windows)
- Cache: `priv/rlm_cache/nyc_311_data.csv`

The download uses a column subset:
- unique_key
- created_date
- agency / agency_name
- complaint_type / descriptor
- borough / city
- status / resolution_description

Ground truth is computed in Python using the standard library `csv` module (no pandas required).

## Queries

The experiment runs 6 queries with increasing difficulty:

| ID | Difficulty | Query Type | Ground Truth |
|----|------------|------------|--------------|
| Q1 | Easy | Count by borough | Exact integer |
| Q2 | Easy | Count by agency | Exact integer |
| Q3 | Medium | Pattern match count | Exact integer |
| Q4 | Easy | Status filter count | Exact integer |
| Q5 | Medium | Aggregation + ranking | Type + count |
| Q6 | Hard | Multi-condition filter | Exact integer |

## Prerequisites

```bash
# Elixir/Erlang
asdf install

# Python venv with DSPy
mix deps.get
mix snakebridge.setup

# Deno (RLM PythonInterpreter)
asdf plugin add deno https://github.com/asdf-community/asdf-deno.git
asdf install

# LLM API key
export GEMINI_API_KEY="your-key"
```

## Run

```bash
mix run --no-start examples/rlm/rlm_data_extraction_experiment_fixed.exs
```

## Results

Observed run: RLM 100% vs Direct 0% on `gemini/gemini-flash-lite-latest`.

```text
$ mix run --no-start examples/rlm/rlm_data_extraction_experiment_fixed.exs
🐍 Checking Python package requirements...

╔══════════════════════════════════════════════════════════════════╗
║           RLM DATA EXTRACTION EXPERIMENT                          ║
║                                                                   ║
║  Testing Recursive Language Model's ability to accurately         ║
║  extract information from large structured datasets where         ║
║  direct LLM approaches fail due to context limitations.           ║
║                                                                   ║
║  Dataset: NYC 311 Service Requests (50,000 records)               ║
║  Source:  data.cityofnewyork.us (Socrata Open Data API)           ║
╚══════════════════════════════════════════════════════════════════╝


================== Step 1: Data Acquisition ==================
  Using cached dataset: priv/rlm_cache/nyc_311_data.csv
  Total rows: 50000
  Columns: unique_key, created_date, agency, agency_name, complaint_type, descriptor, borough, incident_address, city, status, resolution_description
  Boroughs: 6
  Agencies: 15

================ Step 2: Context Construction ================
  Character count: 34,023,997
  Estimated tokens: ~8,505,999
  Row count: 50000
  Context size: Very Large (RLM territory)

================== Step 3: Query Definition ==================
  Q1 [easy]: Simple count by borough
      Query: How many service requests were made in Brooklyn?
      Ground truth: 15348
  Q2 [easy]: Count by agency
      Query: How many requests were handled by NYPD?
      Ground truth: 21438
  Q3 [medium]: Pattern matching count
      Query: How many complaints are related to noise (contain 'Noise' in complaint type)?
      Ground truth: 8481
  Q4 [easy]: Status filtering
      Query: How many requests have status 'Closed'?
      Ground truth: 32358
  Q5 [medium]: Aggregation + ranking
      Query: What is the most common complaint type and how many occurrences does it have?
      Ground truth: "Illegal Parking (8982)"
  Q6 [hard]: Complex multi-condition
      Query: How many noise complaints in Brooklyn were closed?
      Ground truth: 1995

=================== Step 4: RLM Execution ===================

  Running RLM on 6 queries...
  (RLM will store context as Python variable and write code to query it)

  Q1: How many service requests were made in Brooklyn?
      RLM Answer: 15348
      Time: 9357ms
  Q2: How many requests were handled by NYPD?
      RLM Answer: 21438
      Time: 5768ms
  Q3: How many complaints are related to noise (contain 'Noise' in complaint type)?
      RLM Answer: 8481
      Time: 12703ms
  Q4: How many requests have status 'Closed'?
      RLM Answer: 32358
      Time: 9265ms
  Q5: What is the most common complaint type and how many occurrences does it have?
      RLM Answer: Illegal Parking: 8982
      Time: 9064ms
  Q6: How many noise complaints in Brooklyn were closed?
      RLM Answer: 1995
      Time: 13314ms

=============== Step 5: Direct LLM Comparison ===============

  Running Direct LLM on 6 queries...
  (Direct approach: pass truncated context in prompt)

  Context truncated to 30000 chars (0.1% of full data)
  Q1: How many service requests were made in Brooklyn?
      Direct Answer: 17
      Time: 61ms
  Q2: How many requests were handled by NYPD?
      Direct Answer: 73
      Time: 4ms
  Q3: How many complaints are related to noise (contain 'Noise' in complaint type)?
      Direct Answer: 64
      Time: 4ms
  Q4: How many requests have status 'Closed'?
      Direct Answer: 5
      Time: 4ms
  Q5: What is the most common complaint type and how many occurrences does it have?
      Direct Answer: Noise - Residential, 43
      Time: 3ms
  Q6: How many noise complaints in Brooklyn were closed?
      Direct Answer: 1
      Time: 4ms

================ Step 6: Accuracy Evaluation ================
  Q1:
      Ground truth: 15348
      RLM: 15348 -> ✅ CORRECT
      Direct: 17 -> ❌ WRONG
  Q2:
      Ground truth: 21438
      RLM: 21438 -> ✅ CORRECT
      Direct: 73 -> ❌ WRONG
  Q3:
      Ground truth: 8481
      RLM: 8481 -> ✅ CORRECT
      Direct: 64 -> ❌ WRONG
  Q4:
      Ground truth: 32358
      RLM: 32358 -> ✅ CORRECT
      Direct: 5 -> ❌ WRONG
  Q5:
      Ground truth: "Illegal Parking (8982)"
      RLM: Illegal Parking: 8982 -> ✅ CORRECT
      Direct: Noise - Residential, 43 -> ❌ WRONG
  Q6:
      Ground truth: 1995
      RLM: 1995 -> ✅ CORRECT
      Direct: 1 -> ❌ WRONG

========================== Summary ==========================

╔══════════════════════════════════════════════════════════════════╗
║                    RLM EXPERIMENT RESULTS                         ║
╠══════════════════════════════════════════════════════════════════╣
║  Context Size: ~8505999 tokens (50000 rows)              ║
╠══════════════════════════════════════════════════════════════════╣
║                                                                   ║
║  RLM Accuracy:    100.0% (6/6)                           ║
║  Direct Accuracy:   0.0% (0/6)                           ║
║                                                                   ║
╠══════════════════════════════════════════════════════════════════╣
║  CONCLUSION:                                                      ║
║  RLM significantly outperforms direct LLM on structured data. ║
╚══════════════════════════════════════════════════════════════════╝

  Breakdown by difficulty:
    easy: RLM 100.0% vs Direct 0.0%
    medium: RLM 100.0% vs Direct 0.0%
    hard: RLM 100.0% vs Direct 0.0%
```

## Tips

- The cached CSV avoids re-downloading on subsequent runs.
- If you change `@dataset_limit`, ground truth and context size will change.
- Expect longer runtimes for the RLM queries due to code execution over large data.

## References

- RLM Paper: https://alexzhang13.github.io/blog/2025/rlm/
- NYC 311 Data Dictionary: https://data.cityofnewyork.us/Social-Services/311-Service-Requests-from-2010-to-Present/erm2-nwe9
- DSPy Documentation: https://dspy-docs.vercel.app/
