from langchain_community.callbacks.human import HumanApprovalCallbackHandler
from langchain_community.tools import ShellTool
from langchain_openai import ChatOpenAI
from typing import List, Tuple

# Initialize the LLM
llm = ChatOpenAI(model="o3-mini")


def translate_to_shell_command(user_input: str) -> str:
    """Use LLM to translate natural language to shell command"""
    prompt = f"""Convert the following natural language into a single shell command.
For creating or modifying Python files, use appropriate Python syntax, not shell syntax.
Only return the shell command, nothing else. If you cannot convert it to a valid shell command, return "INVALID".

Examples:
- "create a python script that counts from 0 to 10" -> 'echo "for i in range(11):\\n    print(i)" > count.py'
- "show all files" -> "ls"
- "show current directory" -> "pwd"

User request: {user_input}

Shell command:"""

    response = llm.invoke(prompt).content.strip()
    return response if response != "INVALID" else user_input


# Function to determine which commands need approval
def _should_check(serialized_obj: dict) -> bool:
    # Only require approval for shell commands
    return serialized_obj.get("name") == "shell"


# Function to handle command approval
def _approve(_input: str) -> bool:
    # Automatically approve safe commands
    safe_commands = ["ls", "ls -a", "ls -l", "ls -lh", "pwd", "cat README.md", "echo 'hi there' > temp.txt"]
    if _input.strip() in safe_commands:
        return True

    # Ask for approval for other commands
    msg = "Do you approve of the following input? Anything except 'Y'/'Yes' (case-insensitive) will be treated as a no.\n\n"
    msg += _input + "\n"
    resp = input(msg)
    return resp.lower() in ("yes", "y")


# Setup the shell tool with safety callbacks
callbacks = [HumanApprovalCallbackHandler(should_check=_should_check, approve=_approve)]
shell_tool = ShellTool(callbacks=callbacks)

# Store conversation history as list of (role, content) tuples
conversation_history: List[Tuple[str, str]] = []

# Interactive loop
print("Chat started! Type 'quit' to exit.")
print("\nYou can:")
print("- Use natural language to request shell commands")
print("- Create and run Python scripts")
print("- Execute direct shell commands")
print("\nExamples:")
print('- "show all files in current directory"')
print('- "create a python script that counts from 0 to 10"')
print('- "run count.py"')


def explain_result(command: str, result: str, error: bool = False) -> str:
    """Use LLM to explain what happened with the command execution"""
    if error:
        prompt = f"""The following shell command failed:
Command: {command}
Error: {result}

Explain what went wrong in simple terms and how to fix it. Be concise:"""
    else:
        prompt = f"""The following shell command was executed:
Command: {command}
Output: {result}

Explain what happened in simple terms. Be concise:"""

    return llm.invoke(prompt).content.strip()


def process_message(message: str) -> str:
    """
    Process a natural language message, convert it to a shell command, execute it, and return explanation.

    Args:
        message: The natural language input from the user

    Returns:
        str: Explanation of what happened or error message
    """
    try:
        # Translate natural language to shell command
        shell_command = translate_to_shell_command(message)

        # Execute shell command
        result = shell_tool.run(shell_command)

        # Get LLM explanation
        explanation = explain_result(shell_command, result)
        return explanation

    except Exception as e:
        error_message = str(e)
        # Get LLM explanation of the error
        explanation = explain_result(shell_command, error_message, error=True)
        return explanation


def main():
    while True:
        user_input = input("\nYou: ").strip()
        if user_input.lower() in ("quit", "q", "exit"):
            print("Goodbye!")
            break
        else:
            explanation = process_message(user_input)
            print(f"\nSystem: {explanation}")


if __name__ == "__main__":
    main()
