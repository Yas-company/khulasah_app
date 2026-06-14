/**
 * Khulasah Firebase Cloud Functions
 *
 * This is the main entry point for all Cloud Functions.
 *
 * SETUP INSTRUCTIONS:
 * ===================
 * 1. Install dependencies: cd functions && npm install
 * 2. Login to Firebase: firebase login
 * 3. Initialize project: firebase init (select Functions)
 * 4. Deploy: firebase deploy --only functions
 *
 * LOCAL DEVELOPMENT:
 * ==================
 * Run emulator: npm run serve
 * The emulator will be available at http://localhost:5001
 *
 * OPENAI INTEGRATION (Future):
 * ============================
 * When ready to integrate OpenAI:
 * 1. Add openai package: npm install openai
 * 2. Set API key: firebase functions:config:set openai.key="YOUR_API_KEY"
 * 3. Uncomment OpenAI code in src/generateResult.js
 */

const { generateResult } = require("./src/generateResult");

// Export the callable function
exports.generateResult = generateResult;
