/**
 * Khulasah Cloudflare Worker
 *
 * A Cloudflare Worker that connects to OpenRouter for AI-powered
 * PDF summarization and Q&A generation.
 *
 * Deploy: wrangler deploy
 * Configure OPENROUTER_API_KEY secret: wrangler secret put OPENROUTER_API_KEY
 */

const OPENROUTER_URL = 'https://openrouter.ai/api/v1/chat/completions';
const OPENROUTER_MODEL = 'openrouter/auto';

export default {
  async fetch(request, env, ctx) {
    // Handle CORS
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type',
        },
      });
    }

    const url = new URL(request.url);

    // Health check endpoint
    if (url.pathname === '/health') {
      return jsonResponse({ status: 'ok', timestamp: new Date().toISOString() });
    }

    // Generate result endpoint
    if (url.pathname === '/generate-result' && request.method === 'POST') {
      return handleGenerateResult(request, env);
    }

    return jsonResponse({ error: 'Not found' }, 404);
  },
};

async function handleGenerateResult(request, env) {
  console.log('[Generate] Request received');

  let body;
  try {
    body = await request.json();
  } catch (e) {
    return jsonResponse({ success: false, error: 'Invalid JSON body' }, 400);
  }

  const { extractedText, outputType, summaryLength, outputLanguage, fileName } = body;

  // Validate required fields
  if (!extractedText) {
    console.log('[Generate] Error: Missing extractedText');
    return jsonResponse({ success: false, error: 'Missing required field: extractedText' }, 400);
  }

  const apiKey = env.OPENROUTER_API_KEY;
  if (!apiKey) {
    console.log('[Generate] Error: OPENROUTER_API_KEY not configured');
    return jsonResponse({ success: false, error: 'Server configuration error: API key not set' }, 500);
  }

  const lang = outputLanguage || 'ar';
  console.log(`[Generate] Processing file: ${fileName || 'unknown'}`);
  console.log(`[Generate] Output type: ${outputType}, Length: ${summaryLength}, Language: ${lang}`);
  console.log(`[Generate] Text length: ${extractedText.length} characters`);

  try {
    // Build the prompt based on output type and language
    const prompt = buildPrompt(extractedText, outputType, summaryLength, lang);
    const systemPrompt = getSystemPrompt(lang);

    console.log('[Generate] Calling OpenRouter API...');

    // Call OpenRouter API
    const response = await fetch(OPENROUTER_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`,
        'HTTP-Referer': 'https://khulasah.app',
        'X-Title': 'Khulasah App',
      },
      body: JSON.stringify({
        model: OPENROUTER_MODEL,
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: prompt },
        ],
        temperature: 0.7,
        max_tokens: 4000,
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.log(`[Generate] OpenRouter API error: ${response.status} - ${errorText}`);
      return jsonResponse({ success: false, error: `OpenRouter API error: ${response.status}` }, 500);
    }

    const data = await response.json();
    console.log('[Generate] OpenRouter API response received');

    // Extract the content from the response
    const content = data.choices?.[0]?.message?.content;

    if (!content) {
      console.log('[Generate] Error: No content in OpenRouter response');
      return jsonResponse({ success: false, error: 'No content in API response' }, 500);
    }

    // Parse the JSON response from the AI
    const result = parseAIResponse(content, outputType);

    console.log('[Generate] Result parsed successfully');
    console.log(`[Generate] Has summary: ${!!result.summary}, Has Q&A: ${result.questionsAndAnswers?.length || 0}`);

    return jsonResponse(result);
  } catch (error) {
    console.log(`[Generate] Error: ${error.message}`);
    return jsonResponse({ success: false, error: error.message }, 500);
  }
}

/**
 * Get the system prompt for the AI based on output language
 */
function getSystemPrompt(language) {
  if (language === 'en') {
    return `You are an intelligent assistant specialized in summarizing texts and generating questions and answers in English.

Important rules:
1. All responses must be in English only.
2. Write the summary clearly and organized.
3. Extract the main ideas from the text.
4. If asked for questions, write useful questions with accurate answers.
5. The response must be in JSON format only without any additional text.
6. Do not mention any technical details or service names.

Required response format:
{
  "summary": "Summary here if requested",
  "questionsAndAnswers": [
    {"question": "Question", "answer": "Answer"}
  ]
}`;
  }

  // Default: Arabic
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
 * Build the user prompt based on output type, length, and language
 */
function buildPrompt(text, outputType, summaryLength, language) {
  // Truncate text if too long (keep first 15000 chars)
  const maxLength = 15000;
  const truncatedText = text.length > maxLength ? text.substring(0, maxLength) + '...' : text;

  if (language === 'en') {
    return buildEnglishPrompt(truncatedText, outputType, summaryLength);
  }

  // Default: Arabic
  return buildArabicPrompt(truncatedText, outputType, summaryLength);
}

/**
 * Build English prompt
 */
function buildEnglishPrompt(text, outputType, summaryLength) {
  // Determine summary length description
  let lengthDesc = 'medium length';
  if (summaryLength === 'short') {
    lengthDesc = 'short and concise (3-5 paragraphs)';
  } else if (summaryLength === 'long') {
    lengthDesc = 'long and detailed (8-12 paragraphs)';
  } else {
    lengthDesc = 'medium length (5-8 paragraphs)';
  }

  let instruction = '';

  if (outputType === 'summaryOnly') {
    instruction = `Summarize the following text in a ${lengthDesc} format.

Return the response in JSON format as follows:
{"summary": "Summary here", "questionsAndAnswers": []}`;
  } else if (outputType === 'questionsOnly') {
    instruction = `Generate 5-7 important questions with their answers from the following text.

Return the response in JSON format as follows:
{"summary": "", "questionsAndAnswers": [{"question": "Question", "answer": "Answer"}]}`;
  } else {
    // summaryAndQuestions
    instruction = `Summarize the following text in a ${lengthDesc} format, then generate 5-7 important questions with their answers.

Return the response in JSON format as follows:
{"summary": "Summary here", "questionsAndAnswers": [{"question": "Question", "answer": "Answer"}]}`;
  }

  return `${instruction}

Text:
${text}`;
}

/**
 * Build Arabic prompt
 */
function buildArabicPrompt(text, outputType, summaryLength) {
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
${text}`;
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
      questionsAndAnswers: parsed.questionsAndAnswers || [],
    };
  } catch (error) {
    console.log(`[Parse] Error parsing AI response: ${error.message}`);
    console.log(`[Parse] Raw content: ${content.substring(0, 500)}...`);

    // If parsing fails, try to extract text as summary
    return {
      success: true,
      resultType: 'summaryOnly',
      summary: content,
      questionsAndAnswers: [],
    };
  }
}

/**
 * Helper function to return JSON response
 */
function jsonResponse(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
    },
  });
}
