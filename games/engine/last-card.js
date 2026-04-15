/**
 * Elsewhere — Last Card Engine
 * Uno-compatible rules, Elsewhere-branded.
 * "Last Card!" is called when a player has one card left.
 *
 * Runs in-browser. No server needed.
 * All state lives in one plain object — serializable over Agora.
 */

const SUITS = ['♠','♥','♦','♣'];
const VALUES = ['2','3','4','5','6','7','8','9','10','J','Q','K','A'];

// Special card rules
const SPECIALS = {
  '2':  { action: 'draw2' },       // next player draws 2
  'A':  { action: 'skip' },        // next player skipped
  'J':  { action: 'reverse' },     // reverse direction
  'K':  { action: 'wild' },        // wild — choose suit (black K = draw 4)
};

function buildDeck() {
  const deck = [];
  for (const suit of SUITS) {
    for (const value of VALUES) {
      deck.push({ suit, value, id: `${value}${suit}` });
    }
  }
  // Add 2 wild cards (no suit)
  deck.push({ suit: null, value: 'W',  id: 'W1' });
  deck.push({ suit: null, value: 'W',  id: 'W2' });
  deck.push({ suit: null, value: 'W4', id: 'W4-1' }); // draw 4
  deck.push({ suit: null, value: 'W4', id: 'W4-2' }); // draw 4
  return deck;
}

function shuffle(arr) {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

// ─── State factory ───────────────────────────────────────────
export function createGame(playerIds) {
  const deck = shuffle(buildDeck());
  const hands = {};
  playerIds.forEach(id => { hands[id] = []; });

  // Deal 7 cards each
  let deckIdx = 0;
  for (let c = 0; c < 7; c++) {
    for (const id of playerIds) {
      hands[id].push(deck[deckIdx++]);
    }
  }

  // First discard — skip wilds
  let topCard;
  while (true) {
    topCard = deck[deckIdx++];
    if (!topCard.value.startsWith('W')) break;
  }

  return {
    phase: 'playing',       // 'waiting' | 'playing' | 'round-end' | 'game-end'
    players: playerIds,
    hands,
    drawPile: deck.slice(deckIdx),
    discardPile: [topCard],
    currentSuit: topCard.suit,
    currentValue: topCard.value,
    currentPlayerIdx: 0,
    direction: 1,           // 1 = clockwise, -1 = counter-clockwise
    pendingDraw: 0,         // stacked draw-2 / draw-4 count
    lastCard: {},           // { playerId: true } — called last card
    scores: Object.fromEntries(playerIds.map(id => [id, 0])),
    log: [],
  };
}

// ─── Core move validator ─────────────────────────────────────
export function canPlay(state, card) {
  if (state.pendingDraw > 0) {
    // Can only play a matching draw card to stack
    return card.value === '2' || card.value === 'W4';
  }
  if (card.value.startsWith('W')) return true; // wilds always playable
  return card.suit === state.currentSuit || card.value === state.currentValue;
}

// ─── Apply a move ────────────────────────────────────────────
export function applyMove(state, action) {
  const s = deepClone(state);
  const playerId = s.players[s.currentPlayerIdx];

  if (action.type === 'play') {
    const card = action.card;
    // Remove from hand
    s.hands[playerId] = s.hands[playerId].filter(c => c.id !== card.id);
    s.discardPile.push(card);
    s.currentValue = card.value;

    // Handle specials
    if (card.value === '2') {
      s.pendingDraw += 2;
      s.currentSuit = card.suit;
      advance(s);
    } else if (card.value === 'W4') {
      s.pendingDraw += 4;
      // suit chosen via action.chosenSuit
      s.currentSuit = action.chosenSuit || s.currentSuit;
      advance(s);
    } else if (card.value === 'W') {
      s.currentSuit = action.chosenSuit || s.currentSuit;
      advance(s);
    } else if (card.value === 'A') {
      s.currentSuit = card.suit;
      advance(s); // skip — advance twice
      advance(s);
    } else if (card.value === 'J') {
      s.direction *= -1;
      s.currentSuit = card.suit;
      advance(s);
    } else if (card.value === 'K') {
      // Black K = draw 4 wild behaviour already handled above
      s.currentSuit = card.suit;
      advance(s);
    } else {
      s.currentSuit = card.suit;
      advance(s);
    }

    // Last Card declaration
    if (s.hands[playerId].length === 1) {
      s.lastCard[playerId] = false; // must declare before next player acts
    }
    if (s.hands[playerId].length === 0) {
      s.phase = 'round-end';
      s.winner = playerId;
      s.scores[playerId] = (s.scores[playerId] || 0) + calcPoints(s, playerId);
      s.log.push(`${playerId} wins the round!`);
    }
  }

  if (action.type === 'draw') {
    const count = s.pendingDraw > 0 ? s.pendingDraw : 1;
    s.pendingDraw = 0;
    for (let i = 0; i < count; i++) {
      if (s.drawPile.length === 0) reshuffleDeck(s);
      if (s.drawPile.length > 0) s.hands[playerId].push(s.drawPile.pop());
    }
    s.log.push(`${playerId} drew ${count} card${count > 1 ? 's' : ''}`);
    advance(s);
  }

  if (action.type === 'declare-last-card') {
    s.lastCard[playerId] = true;
    s.log.push(`${playerId} called Last Card!`);
  }

  if (action.type === 'catch-no-declare') {
    // Player with 1 card didn't call Last Card — draw 2 penalty
    const target = action.targetId;
    s.lastCard[target] = false;
    for (let i = 0; i < 2; i++) {
      if (s.drawPile.length === 0) reshuffleDeck(s);
      if (s.drawPile.length > 0) s.hands[target].push(s.drawPile.pop());
    }
    s.log.push(`${target} caught not calling Last Card — draws 2!`);
  }

  return s;
}

// ─── Helpers ─────────────────────────────────────────────────
function advance(s) {
  s.currentPlayerIdx = (s.currentPlayerIdx + s.direction + s.players.length) % s.players.length;
}

function reshuffleDeck(s) {
  const top = s.discardPile.pop();
  s.drawPile = shuffle(s.discardPile);
  s.discardPile = [top];
}

function calcPoints(s, winnerId) {
  let pts = 0;
  for (const [pid, hand] of Object.entries(s.hands)) {
    if (pid === winnerId) continue;
    for (const card of hand) {
      if (['J','Q','K','A'].includes(card.value)) pts += 10;
      else if (card.value === '10') pts += 10;
      else if (card.value.startsWith('W')) pts += 20;
      else pts += parseInt(card.value) || 0;
    }
  }
  return pts;
}

function deepClone(obj) {
  return JSON.parse(JSON.stringify(obj));
}

// ─── Card display helpers ────────────────────────────────────
export function cardColor(card) {
  if (!card.suit) return '#e8c96e'; // wild = gold
  return (card.suit === '♥' || card.suit === '♦') ? '#e85d5d' : '#e8e8e8';
}

export function cardLabel(card) {
  if (card.value === 'W')  return '★';
  if (card.value === 'W4') return '★+4';
  return card.value + (card.suit || '');
}

export function playableCards(state, playerId) {
  const hand = state.hands[playerId] || [];
  return hand.filter(c => canPlay(state, c));
}

export function currentPlayer(state) {
  return state.players[state.currentPlayerIdx];
}
