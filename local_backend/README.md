# Khulasah Local Backend

Local Node.js backend for the Khulasah app. Connects to OpenRouter for AI-powered PDF summarization and Q&A generation.

## Requirements

- Node.js 18+
- OpenRouter API key (get one at https://openrouter.ai)

## Setup

```bash
# Navigate to backend folder
cd local_backend

# Install dependencies
npm install

# Copy environment file
cp .env.example .env

# Edit .env and add your OpenRouter API key
# OPENROUTER_API_KEY=your_key_here

# Start the server
npm run dev
```

## Configuration

Edit `.env` file:

| Variable | Description | Default |
|----------|-------------|---------|
| `OPENROUTER_API_KEY` | Your OpenRouter API key | (required) |
| `OPENROUTER_MODEL` | AI model to use | `openrouter/auto` |
| `PORT` | Server port | `3000` |

### Recommended Models

- `openrouter/auto` - Auto-select best model (recommended)
- `anthropic/claude-3.5-sonnet` - High quality
- `openai/gpt-4o-mini` - Fast and affordable
- `google/gemini-pro` - Good for Arabic

## API Endpoints

### Health Check

```bash
curl http://127.0.0.1:3000/health
```

### Generate Result

```bash
curl -X POST http://127.0.0.1:3000/generate-result \
  -H "Content-Type: application/json" \
  -d '{
    "extractedText": "هذا نص تجريبي للاختبار. يحتوي على معلومات مهمة.",
    "outputType": "summaryOnly",
    "summaryLength": "short",
    "fileName": "test.pdf"
  }'
```

### Request Body

| Field | Type | Description |
|-------|------|-------------|
| `extractedText` | string | The extracted text from PDF (required) |
| `outputType` | string | `summaryOnly`, `questionsOnly`, or `summaryAndQuestions` |
| `summaryLength` | string | `short`, `medium`, or `long` |
| `fileName` | string | Original file name (optional) |

### Response

Success:
```json
{
  "success": true,
  "resultType": "summaryOnly",
  "summary": "الملخص هنا...",
  "questionsAndAnswers": []
}
```

With Q&A:
```json
{
  "success": true,
  "resultType": "summaryAndQuestions",
  "summary": "الملخص هنا...",
  "questionsAndAnswers": [
    {"question": "السؤال الأول؟", "answer": "الجواب الأول"},
    {"question": "السؤال الثاني؟", "answer": "الجواب الثاني"}
  ]
}
```

Error:
```json
{
  "success": false,
  "error": "Error message"
}
```

## Running with Flutter

1. Start the backend server:
   ```bash
   cd local_backend && npm run dev
   ```

2. Run the Flutter app in a separate terminal:
   ```bash
   flutter run
   ```

The app will automatically connect to `http://127.0.0.1:3000` for iOS Simulator.

## Troubleshooting

### Server not starting
- Make sure Node.js 18+ is installed
- Check if port 3000 is available
- Verify `.env` file exists with valid API key

### API errors
- Check OpenRouter API key is valid
- Check your OpenRouter account has credits
- Try a different model in `.env`

### Flutter not connecting
- Make sure backend is running before starting Flutter
- For iOS Simulator, use `127.0.0.1` not `localhost`
- Check console logs for connection errors
