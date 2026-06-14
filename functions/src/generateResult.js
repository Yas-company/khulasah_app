/**
 * generateResult Cloud Function
 *
 * Callable function that generates summaries and Q&A from extracted PDF text.
 *
 * INPUT:
 * {
 *   extractedText: string,  // Text extracted from PDF
 *   outputType: string,     // "summary", "qa", "both"
 *   summaryLength: string,  // "short", "medium", "long", "custom"
 *   fileName: string        // Original file name
 * }
 *
 * OUTPUT:
 * {
 *   success: boolean,
 *   summary?: string,
 *   questionsAndAnswers?: Array<{question: string, answer: string}>,
 *   resultType: "summaryOnly" | "questionsOnly" | "summaryAndQuestions",
 *   error?: string
 * }
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { validateInput } = require("./validators");
const { getSummaryPrompt, getQAPrompt } = require("./prompts");

// ============================================================================
// OPENAI INTEGRATION - UNCOMMENT WHEN READY
// ============================================================================
// const OpenAI = require('openai');
//
// // Initialize OpenAI client
// // API key should be set via: firebase functions:config:set openai.key="YOUR_KEY"
// const openai = new OpenAI({
//   apiKey: process.env.OPENAI_API_KEY || functions.config().openai?.key,
// });
//
// /**
//  * Calls OpenAI API to generate content
//  * @param {string} systemPrompt - The system instruction
//  * @param {string} userPrompt - The user's request with content
//  * @returns {Promise<string>} - The generated text
//  */
// async function callOpenAI(systemPrompt, userPrompt) {
//   const response = await openai.chat.completions.create({
//     model: 'gpt-4-turbo-preview', // or 'gpt-3.5-turbo' for lower cost
//     messages: [
//       { role: 'system', content: systemPrompt },
//       { role: 'user', content: userPrompt },
//     ],
//     temperature: 0.7,
//     max_tokens: 4000,
//   });
//
//   return response.choices[0].message.content;
// }
// ============================================================================

/**
 * Main callable function for generating AI results
 */
exports.generateResult = onCall(
  {
    // Function configuration
    timeoutSeconds: 120,
    memory: "256MiB",
    region: "us-central1", // Change to your preferred region
    // Uncomment to require authentication:
    // enforceAppCheck: true,
  },
  async (request) => {
    try {
      // Extract data from request
      const { extractedText, outputType, summaryLength, fileName } = request.data;

      // Validate input
      const validationError = validateInput({
        extractedText,
        outputType,
        summaryLength,
        fileName,
      });

      if (validationError) {
        throw new HttpsError("invalid-argument", validationError);
      }

      // Log the request (for debugging)
      console.log(`Processing request for file: ${fileName}`);
      console.log(`Output type: ${outputType}, Length: ${summaryLength}`);
      console.log(`Text length: ${extractedText.length} characters`);

      // ======================================================================
      // REAL AI GENERATION - UNCOMMENT WHEN OPENAI IS CONFIGURED
      // ======================================================================
      // let summary = null;
      // let questionsAndAnswers = null;
      //
      // if (outputType === 'summary' || outputType === 'both') {
      //   const summaryPrompt = getSummaryPrompt(summaryLength);
      //   summary = await callOpenAI(summaryPrompt, extractedText);
      // }
      //
      // if (outputType === 'qa' || outputType === 'both') {
      //   const qaPrompt = getQAPrompt();
      //   const qaResponse = await callOpenAI(qaPrompt, extractedText);
      //   questionsAndAnswers = JSON.parse(qaResponse);
      // }
      // ======================================================================

      // DUMMY RESPONSE - Remove when real AI is implemented
      const result = generateDummyResult(outputType, summaryLength, fileName);

      return result;
    } catch (error) {
      console.error("Error generating result:", error);

      if (error instanceof HttpsError) {
        throw error;
      }

      throw new HttpsError(
        "internal",
        "حدث خطأ أثناء معالجة الطلب. يرجى المحاولة مرة أخرى."
      );
    }
  }
);

/**
 * Generates dummy result for testing UI
 * TODO: Remove this function when real OpenAI integration is complete
 *
 * @param {string} outputType - Type of output requested
 * @param {string} summaryLength - Requested summary length
 * @param {string} fileName - Original file name
 * @returns {Object} - Dummy result object
 */
function generateDummyResult(outputType, summaryLength, fileName) {
  const lengthLabels = {
    short: "قصير",
    medium: "متوسط",
    long: "طويل",
    custom: "مخصص",
  };

  const lengthLabel = lengthLabels[summaryLength] || "متوسط";

  const dummySummary = `
ملخص تجريبي من Firebase (${lengthLabel})

تم إنشاء هذا الملخص بواسطة Firebase Cloud Functions للملف: ${fileName}

في النسخة النهائية من التطبيق، سيتم استبدال هذا النص بملخص حقيقي يتم إنشاؤه بواسطة الذكاء الاصطناعي (OpenAI GPT-4).

النقاط الرئيسية:
• تم استلام النص المستخرج من الملف بنجاح
• تم تحديد نوع المخرجات: ${outputType}
• تم تحديد طول الملخص: ${lengthLabel}

سيقوم النظام في المستقبل بتحليل المحتوى وإنشاء ملخص شامل يغطي جميع النقاط الرئيسية في الوثيقة باستخدام تقنيات الذكاء الاصطناعي المتقدمة.
`.trim();

  const dummyQA = [
    {
      question: "ما هو الموضوع الرئيسي للوثيقة؟",
      answer: `هذا سؤال تجريبي تم إنشاؤه بواسطة Firebase Cloud Functions. في النسخة النهائية، سيتم إنشاء أسئلة حقيقية بناءً على محتوى الملف "${fileName}".`,
    },
    {
      question: "ما هي النقاط الرئيسية المذكورة؟",
      answer: "سيتم تحليل النص المستخرج وإنشاء قائمة بالنقاط الرئيسية تلقائياً باستخدام الذكاء الاصطناعي من OpenAI.",
    },
    {
      question: "ما هي الاستنتاجات النهائية؟",
      answer: "سيقوم النظام باستخراج الاستنتاجات والتوصيات من الوثيقة وعرضها بشكل منظم.",
    },
    {
      question: "ما هي المصطلحات المهمة في الوثيقة؟",
      answer: "سيتم تحديد المصطلحات والمفاهيم الرئيسية وشرحها بشكل مبسط باستخدام GPT-4.",
    },
    {
      question: "كيف يمكن تطبيق هذه المعلومات؟",
      answer: "سيوفر النظام اقتراحات عملية لكيفية الاستفادة من المعلومات الموجودة في الوثيقة.",
    },
  ];

  // Return based on output type
  switch (outputType) {
    case "summary":
      return {
        success: true,
        summary: dummySummary,
        resultType: "summaryOnly",
      };

    case "qa":
      return {
        success: true,
        questionsAndAnswers: dummyQA,
        resultType: "questionsOnly",
      };

    case "both":
      return {
        success: true,
        summary: dummySummary,
        questionsAndAnswers: dummyQA,
        resultType: "summaryAndQuestions",
      };

    default:
      return {
        success: true,
        summary: dummySummary,
        resultType: "summaryOnly",
      };
  }
}
