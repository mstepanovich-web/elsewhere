/**
 * Elsewhere — Trivia Engine
 * Generates questions via Claude API (client-side).
 * Returns structured JSON the game can render immediately.
 */

const CLAUDE_MODEL = 'claude-sonnet-4-20250514';

export const CATEGORIES = [
  { id: 'general',    label: 'General Knowledge', emoji: '🧠' },
  { id: 'music',      label: 'Music',              emoji: '🎵' },
  { id: 'movies',     label: 'Movies & TV',        emoji: '🎬' },
  { id: 'sports',     label: 'Sports',             emoji: '⚽' },
  { id: 'science',    label: 'Science',            emoji: '🔬' },
  { id: 'history',    label: 'History',            emoji: '📜' },
  { id: 'food',       label: 'Food & Drink',       emoji: '🍕' },
  { id: 'geography',  label: 'Geography',          emoji: '🌍' },
  { id: 'pop_culture',label: 'Pop Culture',        emoji: '⭐' },
  { id: 'tech',       label: 'Technology',         emoji: '💻' },
];

export const DIFFICULTIES = ['Easy', 'Medium', 'Hard'];

// ─── Generate a batch of questions ──────────────────────────
export async function generateQuestions({ category = 'general', difficulty = 'Medium', count = 10 } = {}) {
  const cat = CATEGORIES.find(c => c.id === category) || CATEGORIES[0];

  const prompt = `Generate ${count} trivia questions for a party game.
Category: ${cat.label}
Difficulty: ${difficulty}

Return ONLY valid JSON, no markdown, no preamble:
{
  "questions": [
    {
      "id": "q1",
      "question": "Question text here?",
      "options": ["A) Option 1", "B) Option 2", "C) Option 3", "D) Option 4"],
      "correct": "A",
      "fun_fact": "One interesting sentence about the answer."
    }
  ]
}

Rules:
- Questions must be clearly worded, unambiguous
- One definitively correct answer
- Wrong options should be plausible but clearly wrong on reflection
- Fun fact should be genuinely interesting, 1 sentence max
- Difficulty: Easy = common knowledge, Medium = most adults know, Hard = specialist knowledge`;

  const resp = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: CLAUDE_MODEL,
      max_tokens: 2000,
      messages: [{ role: 'user', content: prompt }]
    })
  });

  if (!resp.ok) throw new Error('Claude API error: ' + resp.status);
  const data = await resp.json();
  const text = data.content?.[0]?.text || '';

  try {
    const clean = text.replace(/```json|```/g, '').trim();
    return JSON.parse(clean).questions;
  } catch (e) {
    throw new Error('Failed to parse questions: ' + e.message);
  }
}

// ─── Game state factory ──────────────────────────────────────
export function createGame({ playerIds, questions, timePerQuestion = 20 }) {
  return {
    phase: 'waiting',       // 'waiting' | 'question' | 'reveal' | 'leaderboard' | 'game-end'
    players: playerIds,
    questions,
    currentQuestionIdx: 0,
    timePerQuestion,
    timer: 0,
    answers: {},            // { playerId: 'A'|'B'|'C'|'D' }
    scores: Object.fromEntries(playerIds.map(id => [id, 0])),
    streak: Object.fromEntries(playerIds.map(id => [id, 0])),
    log: [],
  };
}

// ─── Apply a move ────────────────────────────────────────────
export function applyMove(state, action) {
  const s = JSON.parse(JSON.stringify(state));
  const q = s.questions[s.currentQuestionIdx];

  if (action.type === 'start-question') {
    s.phase = 'question';
    s.answers = {};
    s.timer = s.timePerQuestion;
  }

  if (action.type === 'submit-answer') {
    if (s.phase !== 'question') return s;
    if (s.answers[action.playerId]) return s; // already answered
    s.answers[action.playerId] = {
      answer: action.answer,
      timeRemaining: action.timeRemaining || 0,
    };
    s.log.push(`${action.playerId} answered`);
  }

  if (action.type === 'reveal') {
    s.phase = 'reveal';
    // Score all answers
    for (const [pid, ans] of Object.entries(s.answers)) {
      if (ans.answer === q.correct) {
        // Base 100pts + time bonus (up to 50pts) + streak bonus
        const timeBonus = Math.round((ans.timeRemaining / s.timePerQuestion) * 50);
        const streakBonus = Math.min(s.streak[pid] * 10, 50);
        const pts = 100 + timeBonus + streakBonus;
        s.scores[pid] = (s.scores[pid] || 0) + pts;
        s.streak[pid] = (s.streak[pid] || 0) + 1;
        s.log.push(`${pid} correct! +${pts}pts`);
      } else {
        s.streak[pid] = 0;
      }
    }
    // Players who didn't answer get 0 and lose streak
    for (const pid of s.players) {
      if (!s.answers[pid]) s.streak[pid] = 0;
    }
  }

  if (action.type === 'next-question') {
    s.currentQuestionIdx++;
    if (s.currentQuestionIdx >= s.questions.length) {
      s.phase = 'game-end';
      s.log.push('Game over!');
    } else {
      s.phase = 'waiting';
    }
  }

  return s;
}

// ─── Leaderboard helper ──────────────────────────────────────
export function leaderboard(state) {
  return [...state.players]
    .map(id => ({ id, score: state.scores[id] || 0, streak: state.streak[id] || 0 }))
    .sort((a, b) => b.score - a.score);
}

export function currentQuestion(state) {
  return state.questions[state.currentQuestionIdx];
}
