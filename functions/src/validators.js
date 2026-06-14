/**
 * Input Validators for Khulasah Cloud Functions
 *
 * This file contains validation logic for all incoming requests.
 * Proper validation helps prevent errors and ensures data quality.
 */

/**
 * Maximum allowed text length (in characters)
 * Adjust based on your OpenAI token limits and cost considerations
 */
const MAX_TEXT_LENGTH = 100000; // ~25,000 tokens

/**
 * Minimum text length required for processing
 */
const MIN_TEXT_LENGTH = 50;

/**
 * Valid output types
 */
const VALID_OUTPUT_TYPES = ["summary", "qa", "both"];

/**
 * Valid summary lengths
 */
const VALID_SUMMARY_LENGTHS = ["short", "medium", "long", "custom"];

/**
 * Validates the input data for generateResult function
 *
 * @param {Object} data - Input data object
 * @param {string} data.extractedText - Text extracted from PDF
 * @param {string} data.outputType - Type of output requested
 * @param {string} data.summaryLength - Desired summary length
 * @param {string} data.fileName - Original file name
 * @returns {string|null} - Error message if validation fails, null if valid
 */
function validateInput({ extractedText, outputType, summaryLength, fileName }) {
  // Check required fields
  if (!extractedText || typeof extractedText !== "string") {
    return "النص المستخرج مطلوب";
  }

  if (!outputType || typeof outputType !== "string") {
    return "نوع المخرجات مطلوب";
  }

  if (!summaryLength || typeof summaryLength !== "string") {
    return "طول الملخص مطلوب";
  }

  if (!fileName || typeof fileName !== "string") {
    return "اسم الملف مطلوب";
  }

  // Validate text length
  if (extractedText.length < MIN_TEXT_LENGTH) {
    return `النص قصير جداً. يجب أن يحتوي على ${MIN_TEXT_LENGTH} حرف على الأقل`;
  }

  if (extractedText.length > MAX_TEXT_LENGTH) {
    return `النص طويل جداً. الحد الأقصى هو ${MAX_TEXT_LENGTH} حرف`;
  }

  // Validate output type
  if (!VALID_OUTPUT_TYPES.includes(outputType)) {
    return `نوع المخرجات غير صالح. الخيارات المتاحة: ${VALID_OUTPUT_TYPES.join(", ")}`;
  }

  // Validate summary length
  if (!VALID_SUMMARY_LENGTHS.includes(summaryLength)) {
    return `طول الملخص غير صالح. الخيارات المتاحة: ${VALID_SUMMARY_LENGTHS.join(", ")}`;
  }

  // Validate file name (basic sanitization check)
  if (fileName.length > 255) {
    return "اسم الملف طويل جداً";
  }

  // All validations passed
  return null;
}

/**
 * Sanitizes text input by removing potentially problematic characters
 *
 * @param {string} text - Input text
 * @returns {string} - Sanitized text
 */
function sanitizeText(text) {
  if (!text || typeof text !== "string") {
    return "";
  }

  // Remove null bytes and other control characters (except newlines and tabs)
  return text
    .replace(/\0/g, "")
    .replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, "")
    .trim();
}

/**
 * Truncates text to maximum length if necessary
 *
 * @param {string} text - Input text
 * @param {number} maxLength - Maximum allowed length
 * @returns {string} - Truncated text
 */
function truncateText(text, maxLength = MAX_TEXT_LENGTH) {
  if (!text || text.length <= maxLength) {
    return text;
  }

  // Truncate at word boundary if possible
  const truncated = text.substring(0, maxLength);
  const lastSpace = truncated.lastIndexOf(" ");

  if (lastSpace > maxLength * 0.8) {
    return truncated.substring(0, lastSpace) + "...";
  }

  return truncated + "...";
}

module.exports = {
  validateInput,
  sanitizeText,
  truncateText,
  MAX_TEXT_LENGTH,
  MIN_TEXT_LENGTH,
  VALID_OUTPUT_TYPES,
  VALID_SUMMARY_LENGTHS,
};
