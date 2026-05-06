#!/bin/bash
# Jonotron Long-Term Memory Harness
# Persists conversation history across Jonotron sessions and restores past context

MEMORY_DIR="$HOME/.jonotron_memory"
HISTORY_DIR="$MEMORY_DIR/history"
MAX_CONTEXT_SESSIONS=5

init_memory() {
    mkdir -p "$HISTORY_DIR"
}

load_context() {
    local context_file="$MEMORY_DIR/current_context.txt"
    > "$context_file"
    
    local past_sessions=($(ls -tr "$HISTORY_DIR"/*.jsonl 2>/dev/null | tail -n "$MAX_CONTEXT_SESSIONS"))
    if [ ${#past_sessions[@]} -eq 0 ]; then
        echo "No past Jonotron sessions found. Starting fresh."
        return
    fi
    
    echo "Jonotron loading context from ${#past_sessions[@]} past sessions..."
    for session in "${past_sessions[@]}"; do
        echo "--- PAST JONOTRON SESSION: $(basename "$session") ---" >> "$context_file"
        cat "$session" >> "$context_file"
        echo "" >> "$context_file"
    done
}

save_session() {
    local session_file="$HISTORY_DIR/$(date +%Y%m%d_%H%M%S).jsonl"
    cp "$MEMORY_DIR/current_context.txt" "$session_file" 2>/dev/null
    echo "Jonotron session saved to $session_file"
}

start_jonotron() {
    local context_file="$MEMORY_DIR/current_context.txt"
    if [ -s "$context_file" ]; then
        echo "Jonotron starting with long-term context..."
        cat "$context_file" - | opencode
    else
        opencode
    fi
    save_session
}

init_memory
load_context
start_jonotron
