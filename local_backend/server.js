/**
 * Khulasah Local Backend
 *
 * A local Node.js server that connects to OpenRouter for AI-powered
 * PDF summarization and Q&A generation.
 */

require('dotenv').config();
const express = require('express');
const cors = require('cors');

const app = express();

// Middleware
app.use(cors());
app.use(express.json({ limit: '10mb' }));

// Configuration
const PORT = process.env.PORT || 3000;
const OPENROUTER_API_KEY = process.env.OPENROUTER_API_KEY;
const OPENROUTER_MODEL = process.env.OPENROUTER_MODEL || 'openrouter/auto';
const OPENROUTER_URL = 'https://openrouter.ai/api/v1/chat/completions';

/**
 * Health check endpoint
 */
app.get('/health', (req, res) => {
  console.log('[Health] Health check requested');
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

/**
 * Generate result endpoint
 * Receives extracted PDF text and returns AI-generated summary/Q&A
 */
app.post('/generate-result', async (req, res) => {
  console.log('[Generate] Request received');

  const { extractedText, outputType, summaryLength, fileName } = req.body;

  // Validate required fields
  if (!extractedText) {
    console.log('[Generate] Error: Missing extractedText');
    return res.status(400).json({
      success: false,
      error: 'Missing required field: extractedText'
    });
  }

  if (!OPENROUTER_API_KEY) {
    console.log('[Generate] Error: OPENROUTER_API_KEY not configured');
    return res.status(500).json({
      success: false,
      error: 'Server configuration error: API key not set'
    });
  }

  console.log(`[Generate] Processing file: ${fileName || 'unknown'}`);
  console.log(`[Generate] Output type: ${outputType}, Length: ${summaryLength}`);
  console.log(`[Generate] Text length: ${extractedText.length} characters`);

  try {
    // Build the prompt based on output type
    const prompt = buildPrompt(extractedText, outputType, summaryLength);

    console.log('[Generate] Calling OpenRouter API...');

    // Call OpenRouter API
    const response = await fetch(OPENROUTER_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${OPENROUTER_API_KEY}`,
        'HTTP-Referer': 'https://khulasah.app',
        'X-Title': 'Khulasah App'
      },
      body: JSON.stringify({
        model: OPENROUTER_MODEL,
        messages: [
          {
            role: 'system',
            content: getSystemPrompt()
          },
          {
            role: 'user',
            content: prompt
          }
        ],
        temperature: 0.7,
        max_tokens: 4000
      })
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.log(`[Generate] OpenRouter API error: ${response.status} - ${errorText}`);
      return res.status(500).json({
        success: false,
        error: `OpenRouter API error: ${response.status}`
      });
    }

    const data = await response.json();
    console.log('[Generate] OpenRouter API response received');

    // Extract the content from the response
    const content = data.choices?.[0]?.message?.content;

    if (!content) {
      console.log('[Generate] Error: No content in OpenRouter response');
      return res.status(500).json({
        success: false,
        error: 'No content in API response'
      });
    }

    // Parse the JSON response from the AI
    const result = parseAIResponse(content, outputType);

    console.log('[Generate] Result parsed successfully');
    console.log(`[Generate] Has summary: ${!!result.summary}, Has Q&A: ${result.questionsAndAnswers?.length || 0}`);

    return res.json(result);

  } catch (error) {
    console.log(`[Generate] Error: ${error.message}`);
    return res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

/**
 * Get the system prompt for the AI
 */
function getSystemPrompt() {
  return `أنت مساعد ذكي متخصص في تلخيص النصوص وإنشاء الأسئلة والأجوبة باللغة العربية.

قواعد مهمة:
1. يجب أن تكون جميع الإجابات باللغة العربية فقط.
2. اكتب الملخص بشكل واضح ومنظم.
3. استخرج الأفكار الرئيسية من النص.
4. إذا طُلب منك أسئلة، اكتب أسئلة مفيدة مع إجابات دقيقة.
5. يجب أن يكون الرد بصيغة JSON فقط بدون أي نص إضافي.
6. لا تذكر أي تفاصيل تقنية أو أسماء خدمات.

صيغة الرد المطلوبة:
{
  "summary": "الملخص هنا إذا طُلب",
  "questionsAndAnswers": [
    {"question": "السؤال", "answer": "الجواب"}
  ]
}`;
}

/**
 * Build the user prompt based on output type and length
 */
function buildPrompt(text, outputType, summaryLength) {
  // Truncate text if too long (keep first 15000 chars)
  const maxLength = 15000;
  const truncatedText = text.length > maxLength
    ? text.substring(0, maxLength) + '...'
    : text;

  // Determine summary length description
  let lengthDesc = 'متوسط الطول';
  if (summaryLength === 'short') {
    lengthDesc = 'قصير ومختصر (3-5 فقرات)';
  } else if (summaryLength === 'long') {
    lengthDesc = 'طويل ومفصل (8-12 فقرة)';
  } else {
    lengthDesc = 'متوسط الطول (5-8 فقرات)';
  }

  let instruction = '';

  if (outputType === 'summaryOnly') {
    instruction = `قم بتلخيص النص التالي بشكل ${lengthDesc}.

أعد الرد بصيغة JSON كالتالي:
{"summary": "الملخص هنا", "questionsAndAnswers": []}`;
  } else if (outputType === 'questionsOnly') {
    instruction = `قم بإنشاء 5-7 أسئلة مهمة مع إجاباتها من النص التالي.

أعد الرد بصيغة JSON كالتالي:
{"summary": "", "questionsAndAnswers": [{"question": "السؤال", "answer": "الجواب"}]}`;
  } else {
    // summaryAndQuestions
    instruction = `قم بتلخيص النص التالي بشكل ${lengthDesc}، ثم أنشئ 5-7 أسئلة مهمة مع إجاباتها.

أعد الرد بصيغة JSON كالتالي:
{"summary": "الملخص هنا", "questionsAndAnswers": [{"question": "السؤال", "answer": "الجواب"}]}`;
  }

  return `${instruction}

النص:
${truncatedText}`;
}

/**
 * Parse the AI response and extract structured data
 */
function parseAIResponse(content, outputType) {
  try {
    // Try to extract JSON from the response
    let jsonStr = content;

    // If the response contains markdown code blocks, extract the JSON
    const jsonMatch = content.match(/```(?:json)?\s*([\s\S]*?)```/);
    if (jsonMatch) {
      jsonStr = jsonMatch[1].trim();
    }

    // Try to find JSON object in the response
    const jsonObjMatch = jsonStr.match(/\{[\s\S]*\}/);
    if (jsonObjMatch) {
      jsonStr = jsonObjMatch[0];
    }

    const parsed = JSON.parse(jsonStr);

    // Determine result type
    let resultType = 'summaryOnly';
    if (outputType === 'questionsOnly') {
      resultType = 'questionsOnly';
    } else if (outputType === 'summaryAndQuestions') {
      resultType = 'summaryAndQuestions';
    }

    return {
      success: true,
      resultType: resultType,
      summary: parsed.summary || '',
      questionsAndAnswers: parsed.questionsAndAnswers || []
    };

  } catch (error) {
    console.log(`[Parse] Error parsing AI response: ${error.message}`);
    console.log(`[Parse] Raw content: ${content.substring(0, 500)}...`);

    // If parsing fails, try to extract text as summary
    return {
      success: true,
      resultType: 'summaryOnly',
      summary: content,
      questionsAndAnswers: []
    };
  }
}

// Start server
app.listen(PORT, () => {
  console.log('========================================');
  console.log('  Khulasah Local Backend');
  console.log('========================================');
  console.log(`Server running on http://127.0.0.1:${PORT}`);
  console.log(`Model: ${OPENROUTER_MODEL}`);
  console.log(`API Key configured: ${OPENROUTER_API_KEY ? 'Yes' : 'No'}`);
  console.log('========================================');
});
