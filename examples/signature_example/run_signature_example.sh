#!/bin/bash

# DSPex Dynamic Signature Example Runner
# This script demonstrates the powerful dynamic signature capabilities

echo "🚀 DSPex Dynamic Signature Example"
echo "===================================="
echo ""

# Check if API key is set
if [ -z "$GEMINI_API_KEY" ]; then
    echo "⚠️  Warning: GEMINI_API_KEY environment variable not set"
    echo "   The example will run with mock responses instead of real ML operations"
    echo "   To use real Gemini API, set: export GEMINI_API_KEY='your-api-key'"
    echo ""
fi

# Ensure we're in the right directory
cd "$(dirname "$0")"

# Install dependencies if needed
if [ ! -d "deps" ]; then
    echo "📦 Installing dependencies..."
    mix deps.get
    echo ""
fi

echo "🎯 Available Examples:"
echo "1. Interactive Menu (default)"
echo "2. Run All Examples"
echo "3. Text Analysis Only"
echo "4. Translation Only" 
echo "5. Content Enhancement Only"
echo "6. Creative Writing Only"
echo ""

read -p "Choose an option (1-6, or press Enter for interactive): " choice

case $choice in
    1|"")
        echo "🖥️  Starting Interactive Menu..."
        mix run -e "SignatureExample.CLI.main()"
        ;;
    2)
        echo "🚀 Running All Examples..."
        mix run_all_examples
        ;;
    3)
        echo "🔍 Running Text Analysis Example..."
        mix run_text_analysis
        ;;
    4)
        echo "🌍 Running Translation Example..."
        mix run_translation
        ;;
    5)
        echo "✨ Running Content Enhancement Example..."
        mix run_enhancement
        ;;
    6)
        echo "📚 Running Creative Writing Example..."
        mix run_creative
        ;;
    *)
        echo "❌ Invalid choice. Starting interactive menu..."
        mix run -e "SignatureExample.CLI.main()"
        ;;
esac

echo ""
echo "🎉 Example complete!"
echo "💡 These examples demonstrate DSPex's dynamic signature capabilities:"
echo "   • Multi-input signatures (text + style, text + target_language)"
echo "   • Multi-output signatures (sentiment + summary + keywords + confidence)"
echo "   • Dynamic signature generation and caching"
echo "   • Fallback mechanisms for reliability"
echo "   • Going beyond hardcoded 'question → answer' patterns"