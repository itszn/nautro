#!/usr/bin/env python3
import os
import json
import re
from pathlib import Path

all_function_names = set()
comp_units = set()

def extract_function_info(lines, start_idx):
    """parse multi-line function signature until opening brace"""
    signature_lines = []
    brace_found = False
    
    for i in range(start_idx, len(lines)):
        line = lines[i]
        signature_lines.append(line)
        if '{' in line:
            brace_found = True
            break
    
    if not brace_found:
        return None
    
    # join signature and clean up
    full_sig = ' '.join(line.strip() for line in signature_lines)
    full_sig = re.sub(r'\s+', ' ', full_sig)  # normalize whitespace
    
    # extract function name with optional pub: (pub )?fn NAME(
    name_match = re.search(r'(?:pub\s+)?fn\s+(\w+)\s*\(', full_sig)
    if not name_match:
        return None
    func_name = name_match.group(1)
    
    # extract ALL modifiers before fn (pub, export, inline, etc)
    modifier_match = re.search(r'^(.*?)fn\s+', full_sig)
    modifiers = modifier_match.group(1).strip() if modifier_match else ""
    
    # extract parameters between parentheses
    paren_match = re.search(r'\(([^)]*)\)', full_sig)
    if not paren_match:
        return None
    
    params_str = paren_match.group(1).strip()
    param_names = []
    
    if params_str:
        # split on commas, extract names before ':'
        for param in params_str.split(','):
            param = param.strip()
            if ':' in param:
                name = param.split(':')[0].strip()
                param_names.append(name)
    
    # extract return type after ) and before {
    after_params = full_sig[paren_match.end():].strip()
    ret_type_match = re.match(r'([^{]*)', after_params)
    return_type = ret_type_match.group(1).strip() if ret_type_match else ""
    
    # get indentation from first line
    indent = len(lines[start_idx]) - len(lines[start_idx].lstrip())
    
    return {
        'name': func_name,
        'params': param_names,
        'return_type': return_type,
        'indent': indent,
        'signature_lines': len(signature_lines),
        'modifiers': modifiers
    }

def process_zig_file(input_path, output_path):
    """process single zig file for noinline transformations"""
    with open(input_path, 'r') as f:
        lines = f.readlines()

    file_name = os.path.basename(input_path)
    comp_unit = file_name.replace('.zig','')

    comp_units.add(comp_unit)
    
    output_lines = []
    i = 0
    
    while i < len(lines):
        line = lines[i]

        
        # check for //noinline comment
        if '//noinline' in line.strip():
            output_lines.append(line)  # keep the comment
            
            # find next function declaration
            j = i + 1
            while j < len(lines) and not re.search(r'\s*(?:pub\s+)?(?:export\s+)?(?:inline\s+)?fn\s+\w+\s*\(', lines[j]):
                output_lines.append(lines[j])
                j += 1
            
            if j < len(lines):
                # found function, process it
                func_info = extract_function_info(lines, j)
                if func_info:
                    all_function_names.add(f'{comp_unit}.{func_info["name"]}')
                    all_function_names.add(f'{comp_unit}.{func_info["name"]}_')
                    # get original function lines
                    original_lines = lines[j:j + func_info['signature_lines']]
                    
                    # rename function by adding underscore, keeping all modifiers
                    pattern = rf'({re.escape(func_info["modifiers"])}\s*)?fn\s+{func_info["name"]}\s*\('
                    if func_info['modifiers']:
                        replacement = f'{func_info["modifiers"]} fn {func_info["name"]}_('
                    else:
                        replacement = f'fn {func_info["name"]}_('
                    
                    modified_first_line = re.sub(pattern, replacement, original_lines[0])
                    
                    # output renamed function
                    output_lines.append(modified_first_line)
                    for line in original_lines[1:]:
                        output_lines.append(line)
                    
                    # find end of function body to insert wrapper after
                    brace_count = 0
                    body_start = j + func_info['signature_lines'] - 1
                    body_end = body_start
                    
                    for k in range(body_start, len(lines)):
                        for char in lines[k]:
                            if char == '{':
                                brace_count += 1
                            elif char == '}':
                                brace_count -= 1
                                if brace_count == 0:
                                    body_end = k
                                    break
                        if brace_count == 0:
                            break
                    
                    # copy function body
                    for k in range(body_start + 1, body_end + 1):
                        if k < len(lines):
                            output_lines.append(lines[k])
                    
                    # generate wrapper function WITH SAME MODIFIERS as original
                    indent_str = ' ' * func_info['indent']
                    param_args = ', '.join(func_info['params'])
                    
                    # reconstruct parameter signature from original
                    orig_sig = ''.join(original_lines).strip()
                    param_match = re.search(r'\(([^)]*)\)', orig_sig)
                    param_sig = param_match.group(1) if param_match else ""
                    
                    ret_match = re.search(r'\)\s*([^{]*)', orig_sig)
                    ret_type = ret_match.group(1).strip() if ret_match else ""
                    
                    # wrapper keeps EXACT same signature including modifiers
                    if func_info['modifiers']:
                        wrapper_decl = f"{indent_str}{func_info['modifiers']} fn {func_info['name']}({param_sig}) {ret_type} {{\n"
                    else:
                        wrapper_decl = f"{indent_str}fn {func_info['name']}({param_sig}) {ret_type} {{\n"
                    
                    output_lines.append(f"\n{wrapper_decl}")
                    output_lines.append(f"{indent_str}    return @call(.never_inline, {func_info['name']}_, .{{{param_args}}});\n")
                    output_lines.append(f"{indent_str}}}\n")
                    
                    i = body_end + 1
                    continue
                else:
                    # couldn't parse function, just copy
                    output_lines.append(lines[j])
                    i = j + 1
            else:
                i += 1
        else:
            output_lines.append(line)
            i += 1

    input_lines = output_lines
    output_lines = []
    i = 0

    while i < len(input_lines):
        line = input_lines[i]

        if '//DEBUGONLY' in line.strip():
            # Skip this line and the next one
            i += 2
            continue

        output_lines.append(line)
        i += 1

    
    # write output
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, 'w') as f:
        f.writelines(output_lines)

def main():
    """process all zig files in current directory"""
    input_dir = Path('./src')
    output_dir = Path('./src_preprocessed')
    
    # clean output directory
    if output_dir.exists():
        import shutil
        shutil.rmtree(output_dir)
    output_dir.mkdir(exist_ok=True)
    
    # find and process all .zig files
    zig_files = list(input_dir.rglob('*.zig'))
    
    for zig_file in zig_files:
        if 'src_preprocessed' in str(zig_file):
            continue  # skip output directory
        
        rel_path = zig_file.relative_to(input_dir)
        output_path = output_dir / rel_path
        
        print(f"processing: {zig_file} -> {output_path}")
        process_zig_file(zig_file, output_path)

    with open('comp_units.json','w') as f:
        f.write(json.dumps(list(comp_units)))

if __name__ == '__main__':
    main()