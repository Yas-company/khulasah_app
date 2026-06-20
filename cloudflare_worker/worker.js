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

  const {
    extractedText,
    outputType,
    summaryLength,
    outputLanguage,
    fileName,
    mode = 'single',
    targetWords,
    targetPages,
  } = body;

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
  const validModes = ['single', 'partial', 'final'];
  if (!validModes.includes(mode)) {
    return jsonResponse({ success: false, error: 'Invalid mode' }, 400);
  }

  console.log(`[Generate] Processing file: ${fileName || 'unknown'}`);
  console.log(`[Generate] Mode: ${mode}`);
  console.log(`[Generate] Output type: ${outputType}, Length: ${summaryLength}, Language: ${lang}`);
  console.log(`[Generate] Text length: ${extractedText.length} characters`);
  console.log(`[Worker] summaryLength: ${summaryLength}`);
  console.log(`[Worker] targetWords: ${targetWords || 'not-set'}`);

  try {
    // Build the prompt based on output type and language
    const prompt = buildPrompt(
      extractedText,
      outputType,
      summaryLength,
      lang,
      mode,
      targetWords,
      targetPages,
    );
    const systemPrompt = getSystemPrompt(lang, mode);
    const requestedMaxTokens = getMaxTokens(
      mode,
      outputType,
      summaryLength,
      targetWords,
    );
    const configuredCap = Number(env.OPENROUTER_MAX_TOKENS || requestedMaxTokens);
    const maxTokens = Math.min(requestedMaxTokens, configuredCap);
    console.log(`[Worker] maxTokens: ${maxTokens}`);

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
        max_tokens: maxTokens,
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
function getSystemPrompt(language, mode) {
  const modeRule = mode === 'partial'
    ? 'Return one information-rich section summary. Do not generate questions.'
    : mode === 'final'
      ? 'Create the final user-facing result from ordered summaries covering the complete document.'
      : 'Create the requested result from the provided document text.';

  if (language === 'en') {
    return `You are an intelligent assistant specialized in summarizing texts and generating questions and answers in English.

Important rules:
1. All responses must be in English only.
2. ${modeRule}
3. Write clearly with descriptive headings and organized sections.
4. If asked for questions, write useful questions with accurate answers.
5. The response must be in JSON format only without any additional text.
6. Do not mention any technical details or service names.
7. Preserve arguments, evidence, definitions, examples, important figures, conclusions, and practical implications.

Required response format:
{
  "summary": "Summary here if requested",
  "questionsAndAnswers": [
    {"question": "Question", "answer": "Answer"}
  ]
}`;
  }

  const arabicModeRule = mode === 'partial'
    ? 'أنشئ ملخصًا جزئيًا غنيًا بالمعلومات، ولا تنشئ أسئلة.'
    : mode === 'final'
      ? 'أنشئ النتيجة النهائية للمستخدم من الملخصات المرتبة التي تغطي المستند كاملًا.'
      : 'أنشئ النتيجة المطلوبة من نص المستند المقدم.';

  return `أنت مساعد ذكي متخصص في تلخيص النصوص وإنشاء الأسئلة والأجوبة باللغة العربية.

قواعد مهمة:
1. يجب أن تكون جميع الإجابات باللغة العربية فقط.
2. ${arabicModeRule}
3. اكتب بعناوين واضحة وأقسام منظمة.
4. إذا طُلب منك أسئلة، اكتب أسئلة مفيدة مع إجابات دقيقة.
5. يجب أن يكون الرد بصيغة JSON فقط بدون أي نص إضافي.
6. لا تذكر أي تفاصيل تقنية أو أسماء خدمات.
7. حافظ على الحجج والأدلة والتعريفات والأمثلة والأرقام المهمة والاستنتاجات والتطبيقات العملية.

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
function buildPrompt(
  text,
  outputType,
  summaryLength,
  language,
  mode,
  targetWords,
  targetPages,
) {
  if (language === 'en') {
    return buildEnglishPrompt(
      text,
      outputType,
      summaryLength,
      mode,
      targetWords,
      targetPages,
    );
  }

  return buildArabicPrompt(
    text,
    outputType,
    summaryLength,
    mode,
    targetWords,
    targetPages,
  );
}

/**
 * Build English prompt
 */
function buildEnglishPrompt(
  text,
  outputType,
  summaryLength,
  mode,
  targetWords,
  targetPages,
) {
  const targetInstruction = getEnglishTargetInstruction(
    targetWords,
    targetPages,
  );

  if (mode === 'partial') {
    return `Create a concise but information-rich analytical summary of this section.
Preserve key ideas, evidence, definitions, examples, important figures, and conclusions.
${targetInstruction}
Return JSON only:
{"summary": "Detailed section summary", "questionsAndAnswers": []}

Section text:
${text}`;
  }

  const lengthDesc = getEnglishLengthDescription(summaryLength);
  const finalRule = mode === 'final'
    ? `The input contains ordered summaries covering the complete document. Synthesize them into one coherent ${lengthDesc} result. Connect ideas across sections, remove repetition, and do not describe the input as partial summaries.`
    : `Create a ${lengthDesc} result from the document text.`;

  let instruction = '';

  if (outputType === 'summaryOnly') {
    instruction = `${finalRule}
${targetInstruction}
Use structured sections covering the overview, central themes, important details, evidence or examples, implications, and conclusion.
If the source is shorter than the requested length, remain naturally detailed without inventing information.

Return the response in JSON format as follows:
{"summary": "Summary here", "questionsAndAnswers": []}`;
  } else if (outputType === 'questionsOnly') {
    instruction = `${finalRule}
Generate exactly 5 important questions with accurate, substantive answers.

Return the response in JSON format as follows:
{"summary": "", "questionsAndAnswers": [{"question": "Question", "answer": "Answer"}]}`;
  } else {
    instruction = `${finalRule}
${targetInstruction}
Use structured sections, then generate exactly 5 important questions with accurate, substantive answers.
If the source is shorter than the requested length, remain naturally detailed without inventing information.

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
function buildArabicPrompt(
  text,
  outputType,
  summaryLength,
  mode,
  targetWords,
  targetPages,
) {
  const targetInstruction = getArabicTargetInstruction(
    targetWords,
    targetPages,
  );

  if (mode === 'partial') {
    return `أنشئ ملخصًا تحليليًا موجزًا لكنه غني بالمعلومات لهذا الجزء.
حافظ على الأفكار الأساسية والأدلة والتعريفات والأمثلة والأرقام المهمة والاستنتاجات.
${targetInstruction}
أعد JSON فقط:
{"summary": "ملخص تفصيلي للجزء", "questionsAndAnswers": []}

نص الجزء:
${text}`;
  }

  const lengthDesc = getArabicLengthDescription(summaryLength);
  const finalRule = mode === 'final'
    ? `المدخل يحتوي على ملخصات مرتبة تغطي المستند كاملًا. ادمجها في نتيجة واحدة مترابطة ${lengthDesc}، واربط الأفكار بين الأقسام، واحذف التكرار، ولا تصف المدخل بأنه ملخصات جزئية.`
    : `أنشئ نتيجة ${lengthDesc} من نص المستند.`;

  let instruction = '';

  if (outputType === 'summaryOnly') {
    instruction = `${finalRule}
${targetInstruction}
استخدم أقسامًا منظمة تشمل النظرة العامة، والأفكار المحورية، والتفاصيل المهمة، والأدلة أو الأمثلة، والآثار أو التطبيقات، والخاتمة.
إذا كان المصدر أقصر من الطول المطلوب، فاكتب ملخصًا مفصلًا بطبيعية دون اختلاق معلومات.

أعد الرد بصيغة JSON كالتالي:
{"summary": "الملخص هنا", "questionsAndAnswers": []}`;
  } else if (outputType === 'questionsOnly') {
    instruction = `${finalRule}
أنشئ 5 أسئلة مهمة بالضبط مع إجابات دقيقة وغنية بالمعلومات.

أعد الرد بصيغة JSON كالتالي:
{"summary": "", "questionsAndAnswers": [{"question": "السؤال", "answer": "الجواب"}]}`;
  } else {
    instruction = `${finalRule}
${targetInstruction}
استخدم أقسامًا منظمة، ثم أنشئ 5 أسئلة مهمة بالضبط مع إجابات دقيقة وغنية بالمعلومات.
إذا كان المصدر أقصر من الطول المطلوب، فاكتب ملخصًا مفصلًا بطبيعية دون اختلاق معلومات.

أعد الرد بصيغة JSON كالتالي:
{"summary": "الملخص هنا", "questionsAndAnswers": [{"question": "السؤال", "answer": "الجواب"}]}`;
  }

  return `${instruction}

النص:
${text}`;
}

function getEnglishLengthDescription(summaryLength) {
  if (summaryLength === 'onePage') {
    return 'concise but complete, roughly one page';
  }
  if (summaryLength === 'tenPages') {
    return 'deep and highly detailed, with substantial structured sections';
  }
  if (summaryLength === 'custom') {
    return 'deep and detailed, following the breadth of the source material';
  }
  return 'detailed, with multiple well-developed sections';
}

function getArabicLengthDescription(summaryLength) {
  if (summaryLength === 'onePage') {
    return 'موجزة لكنها مكتملة بما يقارب صفحة واحدة';
  }
  if (summaryLength === 'tenPages') {
    return 'عميقة وشديدة التفصيل مع أقسام منظمة وموسعة';
  }
  if (summaryLength === 'custom') {
    return 'عميقة ومفصلة بما يتناسب مع اتساع المحتوى';
  }
  return 'مفصلة مع عدة أقسام مكتملة';
}

function getEnglishTargetInstruction(targetWords, targetPages) {
  if (!targetWords) return '';
  const pagesText = targetPages ? ` (approximately ${targetPages} pages)` : '';
  return `Write a summary close to ${targetWords} words as much as possible${pagesText}, with clear organization and subheadings when useful.`;
}

function getArabicTargetInstruction(targetWords, targetPages) {
  if (!targetWords) return '';
  const pagesText = targetPages ? ` (ما يقارب ${targetPages} صفحات)` : '';
  return `اكتب ملخصًا قريبًا من ${targetWords} كلمة قدر الإمكان${pagesText}، مع تنظيم واضح وعناوين فرعية عند الحاجة.`;
}

function getMaxTokens(mode, outputType, summaryLength, targetWords) {
  if (mode === 'partial') {
    return targetWords && targetWords >= 850 ? 1400 : 1100;
  }
  if (outputType === 'questionsOnly') {
    return 1500;
  }
  if (outputType === 'summaryAndQuestions') {
    if (summaryLength === 'onePage') return 1800;
    if (summaryLength === 'fivePages') return 3500;
    if (summaryLength === 'tenPages') return 6500;
    return clampTokenEstimate(targetWords, 1800, 6500, 800);
  }
  if (summaryLength === 'onePage') return 1200;
  if (summaryLength === 'fivePages') return 3000;
  if (summaryLength === 'tenPages') return 6000;
  return clampTokenEstimate(targetWords, 1200, 6000, 300);
}

function clampTokenEstimate(targetWords, minimum, maximum, fallbackWords) {
  const words = Number(targetWords || fallbackWords);
  const estimatedTokens = Math.ceil(words * 1.6);
  return Math.max(minimum, Math.min(maximum, estimatedTokens));
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

    const questions = Array.isArray(parsed.questionsAndAnswers)
      ? parsed.questionsAndAnswers
      : [];
    const normalizedQuestions = outputType === 'summaryAndQuestions' ||
      outputType === 'questionsOnly'
      ? questions.slice(0, 5)
      : [];

    return {
      success: true,
      resultType: resultType,
      summary: parsed.summary || '',
      questionsAndAnswers: normalizedQuestions,
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
