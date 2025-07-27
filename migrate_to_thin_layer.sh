#!/bin/bash
# DSPex Three-Layer Architecture Migration Script
# This script migrates DSPex to be a thin orchestration layer

set -e

echo "=== DSPex Three-Layer Architecture Migration ==="
echo "This script will transform DSPex into a thin orchestration layer"
echo "All implementation code will be moved to archive for reference"
echo ""

# Create archive directory
ARCHIVE_DIR="archive_$(date +%Y%m%d_%H%M%S)"
echo "Creating archive directory: $ARCHIVE_DIR"
mkdir -p "$ARCHIVE_DIR"

# Archive implementation directories
echo "Archiving implementation code..."
directories_to_remove=(
    "lib/dspex/contracts"
    "lib/dspex/modules"
    "lib/dspex/llm"
    "lib/dspex/examples"  # Examples should be updated separately
)

for dir in "${directories_to_remove[@]}"; do
    if [ -d "$dir" ]; then
        echo "  Archiving $dir..."
        cp -r "$dir" "$ARCHIVE_DIR/"
    fi
done

# Archive individual implementation files
files_to_remove=(
    "lib/dspex/contract.ex"
    "lib/dspex/contracts.ex"
    "lib/dspex/native.ex"
    "lib/dspex/chain_of_thought.ex"
    "lib/dspex/predict.ex"
    "lib/dspex/program_of_thought.ex"
    "lib/dspex/react.ex"
    "lib/dspex/retrieve.ex"
    "lib/dspex/lm.ex"
    "lib/dspex/models.ex"
    "lib/dspex/modules.ex"
    "lib/dspex/pipeline.ex"
    "lib/dspex/types.ex"
    "lib/dspex/variables.ex"
    "lib/dspex/tools.ex"
)

echo "Archiving individual files..."
for file in "${files_to_remove[@]}"; do
    if [ -f "$file" ]; then
        echo "  Archiving $file..."
        cp "$file" "$ARCHIVE_DIR/"
    fi
done

# Files to keep (orchestration layer)
echo ""
echo "Files to keep:"
echo "  - lib/dspex.ex (main module)"
echo "  - lib/dspex/application.ex (OTP app)"
echo "  - lib/dspex/bridge.ex (defdsyp macro)"
echo "  - lib/dspex/config.ex (configuration)"
echo "  - lib/dspex/session.ex (session helpers)"
echo "  - lib/dspex/settings.ex (settings management)"
echo "  - lib/dspex/context.ex (context management)"
echo "  - lib/dspex/assertions.ex (test helpers)"
echo "  - lib/dspex/utils/ (utilities)"

echo ""
echo "Archive created at: $ARCHIVE_DIR"
echo ""
echo "=== Next Steps ==="
echo "1. Review the archived files to ensure nothing critical is lost"
echo "2. Run 'bash migrate_to_thin_layer.sh --execute' to perform the migration"
echo "3. Update lib/dspex.ex to remove references to deleted modules"
echo "4. Run tests to verify functionality"

if [ "$1" == "--execute" ]; then
    echo ""
    echo "=== EXECUTING MIGRATION ==="
    read -p "This will delete implementation files. Continue? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Remove directories
        for dir in "${directories_to_remove[@]}"; do
            if [ -d "$dir" ]; then
                echo "Removing $dir..."
                rm -rf "$dir"
            fi
        done
        
        # Remove files
        for file in "${files_to_remove[@]}"; do
            if [ -f "$file" ]; then
                echo "Removing $file..."
                rm "$file"
            fi
        done
        
        echo ""
        echo "Migration complete! DSPex is now a thin orchestration layer."
        echo "Don't forget to:"
        echo "  1. Update lib/dspex.ex to use only Bridge APIs"
        echo "  2. Update mix.exs dependencies"
        echo "  3. Run 'mix compile' to check for errors"
        echo "  4. Run tests"
    else
        echo "Migration cancelled."
    fi
fi