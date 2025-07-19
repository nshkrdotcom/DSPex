# Task CORE.3: CI/CD Pipeline Setup

## Task Overview
**ID**: CORE.3  
**Component**: Core Infrastructure  
**Priority**: P1 (High)  
**Estimated Time**: 4 hours  
**Dependencies**: CORE.1, CORE.2 (Project and environment setup must be complete)  
**Status**: Not Started

## Objective
Create a comprehensive CI/CD pipeline using GitHub Actions that runs all test stages (fast, protocol, integration), automates code quality checks (format, credo, dialyzer), enables test coverage reporting, and configures build artifacts.

## Required Reading

### 1. Architecture Documentation
- **File**: `/home/home/p/g/n/dspex/CLAUDE.md`
  - Lines 126-141: Testing Strategy (three-layer architecture)
  - Lines 166-172: Development Commands

### 2. Test Configuration
- **File**: `/home/home/p/g/n/dspex/docs/specs/immediate_implementation/TASKS.md`
  - Lines 360-430: Testing Infrastructure Tasks
  - Understand the three-layer test strategy

### 3. Mix Configuration
- **File**: `/home/home/p/g/n/dspex/mix.exs`
  - Review current project configuration
  - Understand aliases and test setup

## Implementation Steps

### Step 1: Create GitHub Actions Directory Structure
```bash
mkdir -p /home/home/p/g/n/dspex/.github/workflows
mkdir -p /home/home/p/g/n/dspex/.github/actions
```

### Step 2: Create Main CI Workflow
Create `/home/home/p/g/n/dspex/.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

env:
  MIX_ENV: test
  ELIXIR_VERSION: '1.16.0'
  OTP_VERSION: '26.2'
  PYTHON_VERSION: '3.11'

jobs:
  # Job 1: Code Quality Checks
  quality:
    name: Code Quality
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: ${{ env.ELIXIR_VERSION }}
          otp-version: ${{ env.OTP_VERSION }}
      
      - name: Restore dependencies cache
        uses: actions/cache@v3
        with:
          path: |
            deps
            _build
          key: ${{ runner.os }}-mix-${{ hashFiles('**/mix.lock') }}
          restore-keys: ${{ runner.os }}-mix-
      
      - name: Install dependencies
        run: mix deps.get
      
      - name: Check formatting
        run: mix format --check-formatted
      
      - name: Run Credo
        run: mix credo --strict
      
      - name: Restore PLT cache
        uses: actions/cache@v3
        id: plt-cache
        with:
          path: priv/plts
          key: ${{ runner.os }}-plts-${{ hashFiles('**/mix.lock') }}
          restore-keys: ${{ runner.os }}-plts-
      
      - name: Create PLTs
        if: steps.plt-cache.outputs.cache-hit != 'true'
        run: |
          mkdir -p priv/plts
          mix dialyzer --plt
      
      - name: Run Dialyzer
        run: mix dialyzer

  # Job 2: Fast Tests (Layer 1 - Mock Adapter)
  test-fast:
    name: Fast Tests (Mocks)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: ${{ env.ELIXIR_VERSION }}
          otp-version: ${{ env.OTP_VERSION }}
      
      - name: Restore dependencies cache
        uses: actions/cache@v3
        with:
          path: |
            deps
            _build
          key: ${{ runner.os }}-mix-${{ hashFiles('**/mix.lock') }}
          restore-keys: ${{ runner.os }}-mix-
      
      - name: Install dependencies
        run: mix deps.get
      
      - name: Compile test environment
        run: mix compile --warnings-as-errors
      
      - name: Run fast tests
        run: mix test.fast --cover
      
      - name: Upload coverage reports
        uses: actions/upload-artifact@v3
        with:
          name: fast-test-coverage
          path: cover/

  # Job 3: Protocol Tests (Layer 2 - Bridge Mock)
  test-protocol:
    name: Protocol Tests
    runs-on: ubuntu-latest
    needs: test-fast
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: ${{ env.ELIXIR_VERSION }}
          otp-version: ${{ env.OTP_VERSION }}
      
      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: ${{ env.PYTHON_VERSION }}
      
      - name: Restore dependencies cache
        uses: actions/cache@v3
        with:
          path: |
            deps
            _build
          key: ${{ runner.os }}-mix-${{ hashFiles('**/mix.lock') }}
          restore-keys: ${{ runner.os }}-mix-
      
      - name: Install Elixir dependencies
        run: mix deps.get
      
      - name: Cache Python dependencies
        uses: actions/cache@v3
        with:
          path: ~/.cache/pip
          key: ${{ runner.os }}-pip-${{ hashFiles('**/requirements.txt') }}
          restore-keys: ${{ runner.os }}-pip-
      
      - name: Install Python dependencies
        run: |
          python -m pip install --upgrade pip
          pip install -r python/requirements.txt
      
      - name: Run protocol tests
        run: mix test.protocol --cover
      
      - name: Upload coverage reports
        uses: actions/upload-artifact@v3
        with:
          name: protocol-test-coverage
          path: cover/

  # Job 4: Integration Tests (Layer 3 - Full Integration)
  test-integration:
    name: Integration Tests
    runs-on: ubuntu-latest
    needs: test-protocol
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: ${{ env.ELIXIR_VERSION }}
          otp-version: ${{ env.OTP_VERSION }}
      
      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: ${{ env.PYTHON_VERSION }}
      
      - name: Restore dependencies cache
        uses: actions/cache@v3
        with:
          path: |
            deps
            _build
          key: ${{ runner.os }}-mix-${{ hashFiles('**/mix.lock') }}
          restore-keys: ${{ runner.os }}-mix-
      
      - name: Install Elixir dependencies
        run: mix deps.get
      
      - name: Cache Python dependencies
        uses: actions/cache@v3
        with:
          path: ~/.cache/pip
          key: ${{ runner.os }}-pip-${{ hashFiles('**/requirements.txt') }}
          restore-keys: ${{ runner.os }}-pip-
      
      - name: Install Python dependencies
        run: |
          python -m pip install --upgrade pip
          pip install -r python/requirements.txt
      
      - name: Verify Python setup
        run: python python/scripts/verify_setup.py
      
      - name: Run integration tests
        run: mix test.integration --cover
        env:
          PYTHON_PATH: python
      
      - name: Upload coverage reports
        uses: actions/upload-artifact@v3
        with:
          name: integration-test-coverage
          path: cover/

  # Job 5: Coverage Report
  coverage:
    name: Coverage Report
    runs-on: ubuntu-latest
    needs: [test-fast, test-protocol, test-integration]
    steps:
      - uses: actions/checkout@v4
      
      - name: Download all coverage reports
        uses: actions/download-artifact@v3
      
      - name: Set up Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: ${{ env.ELIXIR_VERSION }}
          otp-version: ${{ env.OTP_VERSION }}
      
      - name: Install dependencies
        run: mix deps.get
      
      - name: Merge coverage reports
        run: |
          mix compile
          # Merge coverage data from all test runs
          # This assumes using ExCoveralls
      
      - name: Upload to Codecov
        uses: codecov/codecov-action@v3
        with:
          files: ./cover/excoveralls.json
          fail_ci_if_error: true

  # Job 6: Build Release
  build:
    name: Build Release
    runs-on: ubuntu-latest
    needs: [quality, test-integration]
    if: github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: ${{ env.ELIXIR_VERSION }}
          otp-version: ${{ env.OTP_VERSION }}
      
      - name: Restore dependencies cache
        uses: actions/cache@v3
        with:
          path: |
            deps
            _build
          key: ${{ runner.os }}-mix-${{ hashFiles('**/mix.lock') }}
          restore-keys: ${{ runner.os }}-mix-
      
      - name: Install dependencies
        run: mix deps.get --only prod
      
      - name: Compile release
        run: |
          MIX_ENV=prod mix compile
          MIX_ENV=prod mix release
      
      - name: Upload release artifacts
        uses: actions/upload-artifact@v3
        with:
          name: release-${{ github.sha }}
          path: _build/prod/rel/dspex/
```

### Step 3: Update mix.exs with Test Aliases
Update `/home/home/p/g/n/dspex/mix.exs` to add test aliases:

```elixir
defp aliases do
  [
    # Existing aliases...
    
    # Test layers
    "test.fast": ["test --only mock"],
    "test.protocol": ["test --only protocol"],
    "test.integration": ["test --only integration"],
    "test.all": ["test.fast", "test.protocol", "test.integration"],
    
    # Quality checks
    "quality": ["format", "credo --strict", "dialyzer"],
    "quality.ci": ["format --check-formatted", "credo --strict", "dialyzer"],
    
    # Setup
    setup: ["deps.get", "deps.compile"],
    "setup.ci": ["deps.get", "deps.compile", "compile --warnings-as-errors"]
  ]
end
```

### Step 4: Add Test Coverage Configuration
Update `mix.exs` to add test coverage:

```elixir
def project do
  [
    # ... existing configuration ...
    test_coverage: [tool: ExCoveralls],
    preferred_cli_env: [
      coveralls: :test,
      "coveralls.detail": :test,
      "coveralls.post": :test,
      "coveralls.html": :test,
      "test.fast": :test,
      "test.protocol": :test,
      "test.integration": :test
    ]
  ]
end

defp deps do
  [
    # ... existing deps ...
    {:excoveralls, "~> 0.18", only: :test}
  ]
end
```

### Step 5: Create PR Workflow
Create `/home/home/p/g/n/dspex/.github/workflows/pr.yml`:

```yaml
name: PR Validation

on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  validate-pr:
    name: Validate PR
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      
      - name: Validate PR title
        uses: amannn/action-semantic-pull-request@v5
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      
      - name: Check PR size
        uses: actions/github-script@v6
        with:
          script: |
            const pr = context.payload.pull_request;
            const additions = pr.additions;
            const deletions = pr.deletions;
            const totalChanges = additions + deletions;
            
            if (totalChanges > 1000) {
              core.warning(`This PR contains ${totalChanges} changes. Consider breaking it into smaller PRs.`);
            }
      
      - name: Label PR
        uses: actions/labeler@v4
        with:
          repo-token: "${{ secrets.GITHUB_TOKEN }}"
```

### Step 6: Create Release Workflow
Create `/home/home/p/g/n/dspex/.github/workflows/release.yml`:

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  release:
    name: Create Release
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.16.0'
          otp-version: '26.2'
      
      - name: Build release
        run: |
          mix deps.get --only prod
          MIX_ENV=prod mix compile
          MIX_ENV=prod mix release
      
      - name: Generate changelog
        id: changelog
        uses: metcalfc/changelog-generator@v4.0.1
        with:
          myToken: ${{ secrets.GITHUB_TOKEN }}
      
      - name: Create Release
        uses: actions/create-release@v1
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          tag_name: ${{ github.ref }}
          release_name: Release ${{ github.ref }}
          body: ${{ steps.changelog.outputs.changelog }}
          draft: false
          prerelease: false
      
      - name: Upload Release Asset
        uses: actions/upload-release-asset@v1
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          upload_url: ${{ steps.create_release.outputs.upload_url }}
          asset_path: ./_build/prod/rel/dspex
          asset_name: dspex-${{ github.ref }}.tar.gz
          asset_content_type: application/gzip
```

### Step 7: Create Dependabot Configuration
Create `/home/home/p/g/n/dspex/.github/dependabot.yml`:

```yaml
version: 2
updates:
  # Elixir dependencies
  - package-ecosystem: "mix"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 10
    reviewers:
      - "your-github-username"
    labels:
      - "dependencies"
      - "elixir"
  
  # Python dependencies
  - package-ecosystem: "pip"
    directory: "/python"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 10
    reviewers:
      - "your-github-username"
    labels:
      - "dependencies"
      - "python"
  
  # GitHub Actions
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
    labels:
      - "dependencies"
      - "github-actions"
```

### Step 8: Create CI Badge and Documentation
Update `/home/home/p/g/n/dspex/README.md` to add CI badges:

```markdown
# DSPex

[![CI](https://github.com/your-org/dspex/workflows/CI/badge.svg)](https://github.com/your-org/dspex/actions)
[![Coverage](https://codecov.io/gh/your-org/dspex/branch/main/graph/badge.svg)](https://codecov.io/gh/your-org/dspex)
[![Hex.pm](https://img.shields.io/hexpm/v/dspex.svg)](https://hex.pm/packages/dspex)

<!-- rest of README -->
```

## Acceptance Criteria

- [ ] GitHub Actions workflow created and properly configured
- [ ] Mix test stages configured (fast, protocol, integration)
- [ ] Code quality checks automated (format, credo, dialyzer)
- [ ] Test coverage reporting enabled with ExCoveralls
- [ ] Build artifacts configured for releases
- [ ] PR validation workflow created
- [ ] Release workflow for tagged versions
- [ ] Dependabot configured for dependency updates
- [ ] CI badges added to README

## Expected Deliverables

1. Main CI workflow at `.github/workflows/ci.yml`
2. PR validation workflow at `.github/workflows/pr.yml`
3. Release workflow at `.github/workflows/release.yml`
4. Dependabot config at `.github/dependabot.yml`
5. Updated `mix.exs` with test aliases and coverage configuration
6. README with CI status badges
7. All workflows passing on push

## Testing the Pipeline

After implementation, test the pipeline:

```bash
# Test locally first
mix quality
mix test.all

# Push to a feature branch
git checkout -b feature/ci-setup
git add .
git commit -m "Add CI/CD pipeline"
git push origin feature/ci-setup

# Create a PR and verify all checks pass
# Merge to main and verify deployment workflow
```

## Notes

- Start with a minimal pipeline and add features incrementally
- Ensure secrets are properly configured in GitHub
- Monitor initial runs closely for issues
- Consider adding performance benchmarks in future iterations
- Add notifications for failed builds on main branch