#!/usr/bin/env python3
"""
Admin tool to generate EchoPanel invite codes.

Usage:
    python scripts/generate_invite_code.py --count 1
    python scripts/generate_invite_code.py --batch 10
"""

import argparse
import json
import secrets
import string
from datetime import datetime
from pathlib import Path


INVITE_CODES_FILE = Path(__file__).parent.parent / "server" / "config" / "invite_codes.json"


def generate_invite_code(prefix: str = "ECHOPANEL") -> str:
    """Generate a random invite code."""
    random_chars = ''.join(secrets.choice(string.ascii_uppercase + string.digits) for _ in range(12))
    return f"{prefix}-{random_chars}"


def load_invite_codes() -> dict:
    """Load existing invite codes from JSON file."""
    if INVITE_CODES_FILE.exists():
        with open(INVITE_CODES_FILE, 'r') as f:
            return json.load(f)
    return {"codes": [], "audit_log": []}


def save_invite_codes(data: dict) -> None:
    """Save invite codes to JSON file."""
    INVITE_CODES_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(INVITE_CODES_FILE, 'w') as f:
        json.dump(data, f, indent=2)


def add_invite_code(code: str, notes: str = "") -> dict:
    """Add a new invite code to the database."""
    data = load_invite_codes()
    
    code_entry = {
        "code": code,
        "created_at": datetime.now().isoformat(),
        "notes": notes,
        "used": False,
        "used_at": None,
        "used_by": None
    }
    
    data["codes"].append(code_entry)
    
    audit_entry = {
        "action": "generated",
        "code": code,
        "timestamp": datetime.now().isoformat(),
        "notes": notes
    }
    data["audit_log"].append(audit_entry)
    
    save_invite_codes(data)
    return code_entry


def mark_code_used(code: str, user_id: str = "unknown") -> dict:
    """Mark an invite code as used."""
    data = load_invite_codes()
    
    for code_entry in data["codes"]:
        if code_entry["code"] == code:
            code_entry["used"] = True
            code_entry["used_at"] = datetime.now().isoformat()
            code_entry["used_by"] = user_id
            
            audit_entry = {
                "action": "used",
                "code": code,
                "timestamp": datetime.now().isoformat(),
                "user_id": user_id
            }
            data["audit_log"].append(audit_entry)
            
            save_invite_codes(data)
            return code_entry
    
    return None


def list_invite_codes() -> None:
    """List all invite codes."""
    data = load_invite_codes()
    
    print(f"\nTotal codes: {len(data['codes'])}")
    print(f"Unused codes: {sum(1 for c in data['codes'] if not c['used'])}")
    print(f"Used codes: {sum(1 for c in data['codes'] if c['used'])}")
    print()
    
    for i, code in enumerate(data['codes'], 1):
        status = "✓ USED" if code['used'] else "○ UNUSED"
        print(f"{i}. [{status}] {code['code']}")
        print(f"   Created: {code['created_at']}")
        if code['used']:
            print(f"   Used: {code['used_at']} by {code['used_by']}")
        if code['notes']:
            print(f"   Notes: {code['notes']}")
        print()


def export_codes_receipt(output_file: str = None) -> dict:
    """Export codes receipt for audit."""
    data = load_invite_codes()
    receipt = {
        "generated_at": datetime.now().isoformat(),
        "total_codes": len(data['codes']),
        "unused_codes": sum(1 for c in data['codes'] if not c['used']),
        "codes": [c['code'] for c in data['codes'] if not c['used']],
        "audit_log": data['audit_log']
    }
    
    if output_file:
        with open(output_file, 'w') as f:
            json.dump(receipt, f, indent=2)
        print(f"Receipt exported to: {output_file}")
    
    return receipt


def main():
    parser = argparse.ArgumentParser(description="Generate and manage EchoPanel invite codes")
    subparsers = parser.add_subparsers(dest='command', help='Available commands')
    
    # Generate command
    gen_parser = subparsers.add_parser('generate', help='Generate new invite codes')
    gen_parser.add_argument('--count', type=int, default=1, help='Number of codes to generate')
    gen_parser.add_argument('--prefix', default='ECHOPANEL', help='Code prefix')
    gen_parser.add_argument('--notes', default='', help='Notes for the code(s)')
    
    # Batch command
    batch_parser = subparsers.add_parser('batch', help='Generate batch of codes')
    batch_parser.add_argument('--count', type=int, required=True, help='Number of codes to generate')
    batch_parser.add_argument('--output', help='Output file for receipt')
    
    # Use command
    use_parser = subparsers.add_parser('use', help='Mark code as used')
    use_parser.add_argument('code', help='Invite code to mark as used')
    use_parser.add_argument('--user-id', default='unknown', help='User who used the code')
    
    # List command
    subparsers.add_parser('list', help='List all invite codes')
    
    # Export command
    export_parser = subparsers.add_parser('export', help='Export codes receipt')
    export_parser.add_argument('--output', help='Output file path')
    
    args = parser.parse_args()
    
    if args.command == 'generate':
        for i in range(args.count):
            code = generate_invite_code(args.prefix)
            entry = add_invite_code(code, notes=args.notes or f"Generated in batch of {args.count}")
            print(f"Generated: {code}")
    
    elif args.command == 'batch':
        codes = []
        for i in range(args.count):
            code = generate_invite_code()
            add_invite_code(code, notes=f"Batch generation")
            codes.append(code)
        
        print(f"\nGenerated {args.count} codes")
        for code in codes:
            print(f"  - {code}")
        
        if args.output:
            export_codes_receipt(args.output)
    
    elif args.command == 'use':
        entry = mark_code_used(args.code, args.user_id)
        if entry:
            print(f"Marked code as used: {args.code}")
        else:
            print(f"Code not found: {args.code}")
    
    elif args.command == 'list':
        list_invite_codes()
    
    elif args.command == 'export':
        receipt = export_codes_receipt(args.output)
        print(f"Exported {receipt['total_codes']} codes")


if __name__ == '__main__':
    main()
