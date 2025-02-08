from dotenv import load_dotenv
from flask import Flask, request
import os
from uuid import uuid4
import threading
from openai import OpenAI
from werkzeug.utils import secure_filename

app = Flask(__name__)
load_dotenv()
client = OpenAI(
    api_key=os.getenv("OPENAI_API_KEY")
)

# Configure upload folder and OpenAI
UPLOAD_FOLDER = 'uploads'
TRANSCRIPTIONS_FOLDER = 'transcriptions'
ALLOWED_EXTENSIONS = {'m4a', 'mp3', 'mp4', 'wav'}

# Create uploads directory if it doesn't exist
os.makedirs(UPLOAD_FOLDER, exist_ok=True)
os.makedirs(TRANSCRIPTIONS_FOLDER, exist_ok=True)

task_dict = dict()

def allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

def process_audio(task_id, file_path):
    print("Processing audio, transcribing through whisper: ", file_path)
    try:
        with open(file_path, 'rb') as audio_file:
            transcription = client.audio.transcriptions.create(
                model="whisper-1", 
                file=audio_file
            )
            print(transcription)
            task_dict[task_id]['response'] = transcript['text']
            print("Task complete: ", task_id)
            print("Response: ", transcript['text'])
        with open(f"{TRANSCRIPTIONS_FOLDER}/{task_id}.txt", 'w') as f:
            f.write(transcript['text'])
    

    # TODO: PANNA LOOK HERE
    # Shell script to transcribe audio

    except Exception as e:
        task_dict[task_id]['response'] = f"Error: {str(e)}"
        task_dict[task_id]['error'] = True

@app.route('/upload', methods=['POST', 'GET'])
def upload_file():
    if 'file' not in request.files:
        return {'error': 'No file part'}, 400
    
    file = request.files['file']
    if file.filename == '':
        return {'error': 'No selected file'}, 400
    
    if file and allowed_file(file.filename):
        item_id = str(uuid4())
        filename = secure_filename(f"{item_id}.m4a")
        file_path = os.path.join(UPLOAD_FOLDER, filename)
        file.save(file_path)
        
        task_dict[item_id] = {
            'filename': f"{item_id}.m4a",
            'response': None,
            'error': False
        }
        
        # Start transcription in background
        thread = threading.Thread(
            target=process_audio,
            args=(item_id, file_path)
        )
        thread.start()
        
        return {
            'taskId': item_id,
            'message': 'File uploaded successfully, processing started',
            'filename': f"{item_id}.m4a",
            'path': file_path
        }, 200
    
    return {'error': 'File type not allowed'}, 400

@app.route('/poll/<task_id>', methods=['GET'])
def poll(task_id):
    if task_id not in task_dict:
        return {
            'ready': False,
            'error': 'Task not found'
        }, 404
    
    task = task_dict[task_id]
    if task['response'] is None:
        return {'ready': False}, 200
    
    return {
        'ready': True,
        'message': task['response'],
        'error': task.get('error', False)
    }, 200

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=12000)