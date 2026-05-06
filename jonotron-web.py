#!/usr/bin/env python3
from flask import Flask, render_template_string, request, jsonify
import subprocess, os, datetime, json

app = Flask(__name__)
MEMORY_DIR = os.path.expanduser("~/.jonotron_memory/history")
CHAT_HISTORY = []

HTML_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <title>Jonotron Web Interface</title>
    <style>
        body { font-family: monospace; max-width: 800px; margin: 0 auto; padding: 20px; }
        #chat { border: 1px solid #ccc; height: 500px; overflow-y: scroll; padding: 10px; margin-bottom: 10px; }
        .user { color: #0066cc; margin: 5px 0; }
        .jonotron { color: #ff6600; margin: 5px 0; }
        input { width: 70%; padding: 10px; }
        button { padding: 10px 20px; }
    </style>
</head>
<body>
    <h1>Jonotron Long-Term Memory Interface</h1>
    <div id="chat">
        {% for m in history %}
            <div class="{{ m.role }}">{{ m.role }}: {{ m.content }}</div>
        {% endfor %}
    </div>
    <form id="form">
        <input type="text" id="prompt" placeholder="Enter prompt for Jonotron..." required>
        <button type="submit">Send to Jonotron</button>
    </form>
    <script>
        const form = document.getElementById('form');
        const chat = document.getElementById('chat');
        const input = document.getElementById('prompt');
        
        form.addEventListener('submit', async (e) => {
            e.preventDefault();
            const prompt = input.value;
            if (!prompt) return;
            
            chat.innerHTML += `<div class="user">user: ${prompt}</div>`;
            input.value = '';
            
            const res = await fetch('/send', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({prompt})
            });
            const data = await res.json();
            chat.innerHTML += `<div class="jonotron">jonotron: ${data.response}</div>`;
            chat.scrollTop = chat.scrollHeight;
        });
    </script>
</body>
</html>
"""

def load_history():
    global CHAT_HISTORY
    os.makedirs(MEMORY_DIR, exist_ok=True)
    files = sorted(os.listdir(MEMORY_DIR))[-5:]
    for f in files:
        if f.endswith('.jsonl'):
            with open(os.path.join(MEMORY_DIR, f)) as fh:
                for line in fh:
                    CHAT_HISTORY.append(json.loads(line))

@app.route('/')
def index():
    return render_template_string(HTML_TEMPLATE, history=CHAT_HISTORY)

@app.route('/send', methods=['POST'])
def send():
    prompt = request.json.get('prompt', '')
    if not prompt:
        return jsonify({'response': 'No prompt provided'})
    
    context = '\n'.join([f"{m['role']}: {m['content']}" for m in CHAT_HISTORY[-20:]])
    full_prompt = f"PAST JONOTRON CONTEXT:\n{context}\n\nNEW PROMPT: {prompt}"
    
    try:
        result = subprocess.run(['opencode'], input=full_prompt.encode(), capture_output=True, timeout=60)
        response = result.stdout.decode().strip() or result.stderr.decode().strip()
    except Exception as e:
        response = f"Jonotron error: {str(e)}"
    
    CHAT_HISTORY.append({'role': 'user', 'content': prompt})
    CHAT_HISTORY.append({'role': 'jonotron', 'content': response})
    
    ts = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    with open(os.path.join(MEMORY_DIR, f"{ts}.jsonl"), 'a') as fh:
        fh.write(json.dumps({'role': 'user', 'content': prompt}) + '\n')
        fh.write(json.dumps({'role': 'jonotron', 'content': response}) + '\n')
    
    return jsonify({'response': response})

if __name__ == '__main__':
    load_history()
    print("Jonotron Web Interface running at http://localhost:5000")
    app.run(host='0.0.0.0', port=5000)
