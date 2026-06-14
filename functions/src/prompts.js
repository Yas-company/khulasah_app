/**
 * AI Prompts for Khulasah
 *
 * This file contains all the prompts used for OpenAI API calls.
 * Prompts are designed for Arabic content and optimized for document summarization.
 *
 * CUSTOMIZATION:
 * ==============
 * Modify these prompts to adjust:
 * - Output style and tone
 * - Summary length and detail level
 * - Question types and complexity
 * - Language preferences (Arabic/English)
 */

/**
 * Returns the system prompt for summary generation
 *
 * @param {string} length - Desired summary length: "short", "medium", "long", "custom"
 * @returns {string} - System prompt for OpenAI
 */
function getSummaryPrompt(length) {
  const lengthInstructions = {
    short: "اكتب ملخصاً موجزاً في فقرة أو فقرتين فقط (100-200 كلمة).",
    medium: "اكتب ملخصاً متوسط الطول يغطي النقاط الرئيسية (300-500 كلمة).",
    long: "اكتب ملخصاً شاملاً ومفصلاً يغطي جميع النقاط المهمة (700-1000 كلمة).",
    custom: "اكتب ملخصاً شاملاً بالطول المناسب للمحتوى.",
  };

  const lengthInstruction = lengthInstructions[length] || lengthInstructions.medium;

  return `أنت مساعد ذكي متخصص في تلخيص المستندات باللغة العربية.

مهمتك:
${lengthInstruction}

قواعد التلخيص:
1. استخدم اللغة العربية الفصحى الواضحة
2. حافظ على الأفكار الرئيسية والمعلومات المهمة
3. نظم الملخص بشكل منطقي ومتسلسل
4. استخدم النقاط والعناوين الفرعية عند الحاجة
5. تجنب التكرار والحشو
6. إذا كان النص يحتوي على أرقام أو إحصائيات مهمة، قم بتضمينها
7. اذكر أي استنتاجات أو توصيات رئيسية

الآن، قم بتلخيص النص التالي:`;
}

/**
 * Returns the system prompt for Q&A generation
 *
 * @returns {string} - System prompt for OpenAI
 */
function getQAPrompt() {
  return `أنت مساعد ذكي متخصص في إنشاء أسئلة وأجوبة تعليمية باللغة العربية.

مهمتك:
أنشئ 5-7 أسئلة وأجوبة بناءً على المحتوى المقدم.

قواعد إنشاء الأسئلة:
1. اجعل الأسئلة متنوعة (فهم، تحليل، تطبيق)
2. تأكد أن الإجابات موجودة في النص
3. استخدم اللغة العربية الفصحى الواضحة
4. اجعل الإجابات شاملة ولكن موجزة
5. رقم الأسئلة بالتسلسل

قم بإرجاع النتيجة كمصفوفة JSON بالتنسيق التالي:
[
  {"question": "السؤال الأول؟", "answer": "الإجابة على السؤال الأول."},
  {"question": "السؤال الثاني؟", "answer": "الإجابة على السؤال الثاني."}
]

لا تضف أي نص إضافي قبل أو بعد مصفوفة JSON.

الآن، أنشئ الأسئلة والأجوبة للنص التالي:`;
}

/**
 * Returns prompt for combined summary and Q&A
 *
 * @param {string} length - Desired summary length
 * @returns {string} - Combined system prompt
 */
function getCombinedPrompt(length) {
  return `${getSummaryPrompt(length)}

بعد الملخص، أنشئ أيضاً 3-5 أسئلة وأجوبة رئيسية عن المحتوى.

قم بإرجاع النتيجة بتنسيق JSON:
{
  "summary": "الملخص هنا...",
  "questionsAndAnswers": [
    {"question": "السؤال؟", "answer": "الإجابة."}
  ]
}`;
}

module.exports = {
  getSummaryPrompt,
  getQAPrompt,
  getCombinedPrompt,
};
