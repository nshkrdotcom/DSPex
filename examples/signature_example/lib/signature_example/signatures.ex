defmodule SignatureExample.Signatures do
  @moduledoc """
  Dynamic signature definitions for the DSPex signature example.
  
  This module demonstrates how to define complex signatures with multiple
  inputs and outputs, going beyond the basic "question → answer" pattern.
  """

  @doc """
  Text analysis signature for comprehensive content analysis.
  
  Inputs:
  - text: The content to analyze
  - style: The analysis style (brief, detailed, academic)
  
  Outputs:
  - sentiment: Detected sentiment (positive, negative, neutral)
  - summary: A concise summary of the content
  - keywords: Key terms extracted from the text
  - confidence_score: Confidence in the analysis (0.0-1.0)
  """
  def text_analysis_signature do
    %{
      name: "TextAnalysisSignature",
      description: "Comprehensive text analysis with sentiment, summary, and keyword extraction",
      inputs: [
        %{
          name: "text", 
          type: "string", 
          description: "The input text to analyze for sentiment, content, and key themes"
        },
        %{
          name: "style", 
          type: "string", 
          description: "Analysis style: 'brief' for quick analysis, 'detailed' for comprehensive analysis, 'academic' for scholarly analysis"
        }
      ],
      outputs: [
        %{
          name: "sentiment", 
          type: "string", 
          description: "Detected sentiment: positive, negative, or neutral"
        },
        %{
          name: "summary", 
          type: "string", 
          description: "A concise summary capturing the main points of the text"
        },
        %{
          name: "keywords", 
          type: "string", 
          description: "Key terms and phrases extracted from the text, comma-separated"
        },
        %{
          name: "confidence_score", 
          type: "string", 
          description: "Confidence level in the analysis (high, medium, low)"
        }
      ]
    }
  end

  @doc """
  Translation signature for converting text between languages.
  
  Inputs:
  - text: The content to translate
  - target_language: The desired output language
  
  Outputs:
  - translated_text: The translated content
  - source_language: Detected source language
  - confidence_score: Translation confidence level
  """
  def translation_signature do
    %{
      name: "TranslationSignature",
      description: "Text translation with language detection and confidence scoring",
      inputs: [
        %{
          name: "text", 
          type: "string", 
          description: "The text content to translate to another language"
        },
        %{
          name: "target_language", 
          type: "string", 
          description: "Target language for translation (e.g., 'spanish', 'french', 'german', 'japanese')"
        }
      ],
      outputs: [
        %{
          name: "translated_text", 
          type: "string", 
          description: "The text translated into the target language"
        },
        %{
          name: "source_language", 
          type: "string", 
          description: "The detected source language of the input text"
        },
        %{
          name: "confidence_score", 
          type: "string", 
          description: "Translation confidence level (high, medium, low)"
        }
      ]
    }
  end

  @doc """
  Content enhancement signature for improving text quality.
  
  Inputs:
  - text: The original content to enhance
  - enhancement_type: Type of enhancement (clarity, engagement, formality)
  - tone: Desired tone (professional, casual, friendly)
  
  Outputs:
  - enhanced_text: The improved version of the text
  - changes_made: Description of what was changed
  - readability_score: Assessment of text readability
  """
  def content_enhancement_signature do
    %{
      name: "ContentEnhancementSignature", 
      description: "Content improvement with tone adjustment and readability optimization",
      inputs: [
        %{
          name: "text", 
          type: "string", 
          description: "Original text content that needs improvement or enhancement"
        },
        %{
          name: "enhancement_type", 
          type: "string", 
          description: "Type of enhancement: 'clarity' for clearer expression, 'engagement' for more engaging content, 'formality' for formal tone"
        },
        %{
          name: "tone", 
          type: "string", 
          description: "Desired tone: 'professional' for business context, 'casual' for informal context, 'friendly' for approachable tone"
        }
      ],
      outputs: [
        %{
          name: "enhanced_text", 
          type: "string", 
          description: "The improved version of the original text with requested enhancements"
        },
        %{
          name: "changes_made", 
          type: "string", 
          description: "Summary of specific changes and improvements made to the original text"
        },
        %{
          name: "readability_score", 
          type: "string", 
          description: "Assessment of text readability (excellent, good, average, poor)"
        }
      ]
    }
  end

  @doc """
  Creative writing signature for generating stories and creative content.
  
  Inputs:
  - prompt: Writing prompt or theme
  - genre: Desired genre (fantasy, sci-fi, mystery, romance)
  - length: Desired length (short, medium, long)
  
  Outputs:
  - story: The generated creative content
  - theme: Main theme or moral of the story
  - character_count: Number of characters in the story
  """
  def creative_writing_signature do
    %{
      name: "CreativeWritingSignature",
      description: "Creative story generation with theme analysis and character counting",
      inputs: [
        %{
          name: "prompt", 
          type: "string", 
          description: "Writing prompt, theme, or scenario to base the creative content on"
        },
        %{
          name: "genre", 
          type: "string", 
          description: "Desired genre: 'fantasy', 'sci-fi', 'mystery', 'romance', 'adventure', 'drama'"
        },
        %{
          name: "length", 
          type: "string", 
          description: "Desired story length: 'short' (1-2 paragraphs), 'medium' (3-5 paragraphs), 'long' (6+ paragraphs)"
        }
      ],
      outputs: [
        %{
          name: "story", 
          type: "string", 
          description: "The generated creative story or content based on the prompt and specifications"
        },
        %{
          name: "theme", 
          type: "string", 
          description: "Main theme, moral, or message conveyed by the generated story"
        },
        %{
          name: "character_count", 
          type: "string", 
          description: "Approximate number of characters in the generated story"
        }
      ]
    }
  end
end