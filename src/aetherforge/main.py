# file: src/aetherforge/main.py
import os
import sys
from openai import OpenAI
from dotenv import load_dotenv


def main():
    load_dotenv()
    base_url = os.environ.get("BASE_URL", "http://localhost:11434/v1")
    model = os.environ.get("MODEL_NAME", "llama3.1:8b")
    api_key = os.environ.get("API_KEY", "local")  # any non-empty value works for local servers

    print(f"[AetherForge] connecting to {base_url} model={model}")
    try:
        client = OpenAI(base_url=base_url, api_key=api_key)
        resp = client.chat.completions.create(
            model=model,
            messages=[{"role": "user", "content": "Respond exactly: AetherForge online."}],
            temperature=0,
            max_tokens=8,
        )
        print(resp.choices[0].message.content.strip())
    except Exception as e:
        print("[AetherForge] startup check failed.")
        print("Hint: ensure your local runner (Ollama or vLLM) is up and BASE_URL points to it.")
        print(f"Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
