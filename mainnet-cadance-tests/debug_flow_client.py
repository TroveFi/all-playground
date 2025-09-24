# debug_flow_client.py
# Debug version to see what's happening with Flow CLI output

import subprocess
import json
import re

def debug_flow_output():
    """Debug the Flow CLI output parsing"""
    print("Testing Flow CLI output parsing...")
    
    cmd = ["flow", "scripts", "execute", "cadence/scripts/get-increment-pools.cdc", "--network=mainnet"]
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        
        print("=== RAW STDOUT ===")
        print(result.stdout)
        print("=== END RAW STDOUT ===")
        
        # Split into lines
        output_lines = result.stdout.strip().split('\n')
        
        print(f"\nNumber of lines: {len(output_lines)}")
        for i, line in enumerate(output_lines):
            print(f"Line {i}: '{line}'")
        
        # Try to find Result line
        result_line = None
        for line in output_lines:
            if line.startswith('Result:'):
                result_line = line[7:].strip()
                break
        
        if result_line:
            print(f"\nFound Result line: '{result_line}'")
            
            # Try to parse as JSON
            try:
                parsed = json.loads(result_line)
                print(f"Successfully parsed as JSON: {type(parsed)}")
                print(f"Content: {parsed}")
            except json.JSONDecodeError:
                print("Not valid JSON, trying to parse Flow struct format...")
                print(f"First 200 chars: '{result_line[:200]}...'")
                
                # Check if it's an array
                if result_line.startswith('[') and 'FarmPoolInfo' in result_line:
                    print("Detected array of FarmPoolInfo structs")
                    # Try to extract individual structs
                    structs = extract_structs(result_line)
                    print(f"Found {len(structs)} structs")
                    for i, struct in enumerate(structs[:2]):  # Show first 2
                        print(f"Struct {i}: {struct[:100]}...")
        else:
            print("No Result: line found in output")
            
    except subprocess.CalledProcessError as e:
        print(f"Command failed: {e}")
        print(f"STDERR: {e.stderr}")

def extract_structs(flow_output):
    """Extract individual structs from Flow output"""
    structs = []
    
    # Find all FarmPoolInfo structs
    pattern = r's\.[a-f0-9]+\.FarmPoolInfo\([^)]+\)'
    matches = re.findall(pattern, flow_output)
    
    return matches

def parse_single_struct(struct_str):
    """Parse a single FarmPoolInfo struct"""
    print(f"Parsing struct: {struct_str[:100]}...")
    
    # Extract values using regex
    fields = {}
    
    # Extract pid
    pid_match = re.search(r'pid:\s*(\d+)', struct_str)
    if pid_match:
        fields['pid'] = int(pid_match.group(1))
    
    # Extract status
    status_match = re.search(r'status:\s*"([^"]*)"', struct_str)
    if status_match:
        fields['status'] = status_match.group(1)
    
    # Extract acceptTokenKey
    token_match = re.search(r'acceptTokenKey:\s*"([^"]*)"', struct_str)
    if token_match:
        fields['acceptTokenKey'] = token_match.group(1)
    
    # Extract totalStaking
    staking_match = re.search(r'totalStaking:\s*([\d.]+)', struct_str)
    if staking_match:
        fields['totalStaking'] = float(staking_match.group(1))
    
    # Extract rewardTokens array
    reward_tokens_match = re.search(r'rewardTokens:\s*\[([^\]]*)\]', struct_str)
    if reward_tokens_match:
        tokens_str = reward_tokens_match.group(1)
        # Parse token array
        tokens = re.findall(r'"([^"]*)"', tokens_str)
        fields['rewardTokens'] = tokens
    
    # Extract rewardInfo dict
    reward_info_match = re.search(r'rewardInfo:\s*\{([^}]*)\}', struct_str)
    if reward_info_match:
        info_str = reward_info_match.group(1)
        # Parse key-value pairs
        pairs = re.findall(r'"([^"]*)"\s*:\s*"([^"]*)"', info_str)
        fields['rewardInfo'] = dict(pairs)
    
    return fields

def test_parsing():
    """Test the parsing with a sample struct"""
    sample = '''s.ccc0fcfe69224dea81ce02ef7617c2ed800b20b68b111d8b13413a5b6a5a0466.FarmPoolInfo(pid: 0, status: "2", acceptTokenKey: "A.fa82796435e15832.SwapPair", totalStaking: 130.14440688, limitAmount: 184467440737.09551615, creator: 0x1b77ba4b414de352, rewardTokens: ["A.b19436aae4d94622.FiatToken"], rewardInfo: {"A.b19436aae4d94622.FiatToken": "RPS: 0.07293684"})'''
    
    parsed = parse_single_struct(sample)
    print(f"Parsed struct: {parsed}")

if __name__ == "__main__":
    debug_flow_output()
    print("\n" + "="*50)
    print("Testing struct parsing...")
    test_parsing()