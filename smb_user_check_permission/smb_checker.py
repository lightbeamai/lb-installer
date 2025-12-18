#!/usr/bin/env python3
"""
SMB Share Access Checker
Tests read access to all shares on an SMB server
pip install pysmb
python smb_checker.py --server 192.168.1.1 --username abc@def.com --password yourpassword
"""

import argparse
import sys
from smb.SMBConnection import SMBConnection
from nmb.NetBIOS import NetBIOS
import socket

def get_netbios_name(ip):
    """Try to get NetBIOS name from IP address"""
    try:
        nb = NetBIOS()
        names = nb.queryIPForName(ip, timeout=2)
        nb.close()
        if names:
            return names[0]
    except:
        pass
    return ip

def list_shares(server, username, password, domain=''):
    """List all available shares on the server"""
    try:
        # Extract domain from username if present
        if '@' in username:
            user_part, domain_part = username.split('@', 1)
            if not domain:
                domain = domain_part
            username = user_part
        elif '\\' in username:
            domain_part, user_part = username.split('\\', 1)
            if not domain:
                domain = domain_part
            username = user_part
        
        # Get NetBIOS name
        netbios_name = get_netbios_name(server)
        
        # Establish connection
        conn = SMBConnection(username, password, socket.gethostname(), 
                            netbios_name, domain=domain, 
                            use_ntlm_v2=True, is_direct_tcp=True)
        
        if not conn.connect(server, 445):
            print(f"Failed to connect to {server}")
            return None
        
        # Get list of shares
        shares = conn.listShares()
        conn.close()
        
        return shares
    except Exception as e:
        print(f"Error listing shares: {e}")
        return None

def test_share_access(server, username, password, share_name, domain=''):
    """Test read access to a specific share"""
    try:
        # Extract domain from username if present
        if '@' in username:
            user_part, domain_part = username.split('@', 1)
            if not domain:
                domain = domain_part
            username = user_part
        elif '\\' in username:
            domain_part, user_part = username.split('\\', 1)
            if not domain:
                domain = domain_part
            username = user_part
        
        # Get NetBIOS name
        netbios_name = get_netbios_name(server)
        
        # Establish connection
        conn = SMBConnection(username, password, socket.gethostname(), 
                            netbios_name, domain=domain,
                            use_ntlm_v2=True, is_direct_tcp=True)
        
        if not conn.connect(server, 445):
            return False, "Connection failed"
        
        # Try to list directory contents
        try:
            files = conn.listPath(share_name, '/')
            conn.close()
            return True, f"✓ READ ACCESS ({len(files)} items)"
        except Exception as e:
            conn.close()
            error_msg = str(e)
            if "ACCESS_DENIED" in error_msg or "STATUS_ACCESS_DENIED" in error_msg:
                return False, "✗ ACCESS DENIED"
            else:
                return False, f"✗ ERROR: {error_msg[:50]}"
    
    except Exception as e:
        return False, f"✗ CONNECTION ERROR: {str(e)[:50]}"

def main():
    parser = argparse.ArgumentParser(
        description='Test read access to SMB shares',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
Examples:
  %(prog)s --server 172.19.32.43 --username ncampos@crestlinehotels.com --password mypass
  %(prog)s -s 172.19.32.43 -u DOMAIN\\user -p mypass
        '''
    )
    
    parser.add_argument('-s', '--server', required=True,
                       help='SMB server IP address or hostname')
    parser.add_argument('-u', '--username', required=True,
                       help='Username (can include domain: user@domain or DOMAIN\\user)')
    parser.add_argument('-p', '--password', required=True,
                       help='Password')
    parser.add_argument('-d', '--domain', default='',
                       help='Domain (optional, can be extracted from username)')
    parser.add_argument('--share', default=None,
                       help='Test only a specific share')
    
    args = parser.parse_args()
    
    print(f"\n{'='*70}")
    print(f"SMB Share Access Checker")
    print(f"{'='*70}")
    print(f"Server: {args.server}")
    print(f"Username: {args.username}")
    print(f"{'='*70}\n")
    
    # If specific share is requested
    if args.share:
        print(f"Testing share: {args.share}")
        has_access, msg = test_share_access(args.server, args.username, 
                                           args.password, args.share, args.domain)
        print(f"  {msg}")
        sys.exit(0 if has_access else 1)
    
    # List all shares
    print("Retrieving share list...")
    shares = list_shares(args.server, args.username, args.password, args.domain)
    
    if shares is None:
        print("Failed to retrieve shares")
        sys.exit(1)
    
    # Filter out IPC$ and ADMIN shares, test the rest
    accessible_shares = []
    denied_shares = []
    error_shares = []
    
    print(f"\nTesting {len(shares)} shares...\n")
    
    for share in shares:
        share_name = share.name
        
        # Skip IPC$ and administrative shares for cleaner output
        skip_shares = ['IPC$', 'ADMIN$']
        if share_name in skip_shares:
            continue
        
        # Test access
        has_access, msg = test_share_access(args.server, args.username, 
                                           args.password, share_name, args.domain)
        
        print(f"{share_name:30s} {msg}")
        
        if has_access:
            accessible_shares.append(share_name)
        elif "ACCESS DENIED" in msg:
            denied_shares.append(share_name)
        else:
            error_shares.append(share_name)
    
    # Summary
    print(f"\n{'='*70}")
    print(f"SUMMARY")
    print(f"{'='*70}")
    print(f"Accessible shares: {len(accessible_shares)}")
    print(f"Denied shares: {len(denied_shares)}")
    print(f"Error/Unknown: {len(error_shares)}")
    print(f"{'='*70}\n")
    
    if accessible_shares:
        print("Shares with READ access:")
        for share in accessible_shares:
            print(f"  • {share}")
        print()

if __name__ == '__main__':
    main()