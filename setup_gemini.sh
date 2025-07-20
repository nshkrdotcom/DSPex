#!/bin/bash

# DSPex Gemini Setup Helper
echo "================================================"
echo "         DSPex Gemini 2.0 Flash Setup           "
echo "================================================"
echo ""

# Check if API key is already set
if [ -n "$GOOGLE_API_KEY" ] || [ -n "$GEMINI_API_KEY" ]; then
    echo "✓ Gemini API key is already configured!"
    if [ -n "$GOOGLE_API_KEY" ]; then
        echo "  GOOGLE_API_KEY: ${GOOGLE_API_KEY:0:6}...${GOOGLE_API_KEY: -4}"
    fi
    if [ -n "$GEMINI_API_KEY" ]; then
        echo "  GEMINI_API_KEY: ${GEMINI_API_KEY:0:6}...${GEMINI_API_KEY: -4}"
    fi
    echo ""
    echo "You're ready to run the examples!"
    exit 0
fi

echo "No Gemini API key found. Let's set it up!"
echo ""
echo "Step 1: Get your free Gemini API key"
echo "--------------------------------------"
echo "Visit: https://makersuite.google.com/app/apikey"
echo ""
echo "Press Enter when you have your API key..."
read

echo ""
echo "Step 2: Enter your API key"
echo "--------------------------"
echo -n "Paste your Gemini API key here: "
read -s API_KEY
echo ""

if [ -z "$API_KEY" ]; then
    echo "❌ No API key entered. Exiting..."
    exit 1
fi

echo ""
echo "Step 3: Choose how to save the API key"
echo "--------------------------------------"
echo "1) Export for current session only"
echo "2) Add to ~/.bashrc (permanent)"
echo "3) Add to ~/.zshrc (permanent)"
echo "4) Just show the export command"
echo ""
echo -n "Choose option (1-4): "
read OPTION

case $OPTION in
    1)
        echo ""
        echo "Run this command in your terminal:"
        echo ""
        echo "export GOOGLE_API_KEY='$API_KEY'"
        echo ""
        echo "Then run the examples!"
        ;;
    2)
        echo "export GOOGLE_API_KEY='$API_KEY'" >> ~/.bashrc
        echo ""
        echo "✓ Added to ~/.bashrc"
        echo ""
        echo "Run: source ~/.bashrc"
        echo "Then run the examples!"
        ;;
    3)
        echo "export GOOGLE_API_KEY='$API_KEY'" >> ~/.zshrc
        echo ""
        echo "✓ Added to ~/.zshrc"
        echo ""
        echo "Run: source ~/.zshrc"
        echo "Then run the examples!"
        ;;
    4)
        echo ""
        echo "export GOOGLE_API_KEY='$API_KEY'"
        echo ""
        ;;
    *)
        echo "Invalid option. Showing export command:"
        echo ""
        echo "export GOOGLE_API_KEY='$API_KEY'"
        echo ""
        ;;
esac

echo ""
echo "================================================"
echo "Setup complete! Now you can run:"
echo ""
echo "mix run examples/dspy/01_question_answering_pipeline.exs"
echo "================================================"