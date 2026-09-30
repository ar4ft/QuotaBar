#!/usr/bin/env python3
"""Create and sign a single-release Sparkle feed for GitHub Releases."""
import base64
import email.utils
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parent.parent
info = plistlib.loads((root / 'dist/QuotaBar.app/Contents/Info.plist').read_bytes())
tag = sys.argv[1] if len(sys.argv) == 2 else ''
if tag != 'v' + info['CFBundleShortVersionString']:
    raise SystemExit('Release tag must match the packaged application version.')
public = base64.b64decode(os.environ['UPDATE_PUBLIC_KEY'].strip(), validate=True)
private_string = os.environ['SPARKLE_PRIVATE_KEY'].strip()
private = base64.b64decode(private_string, validate=True)
if len(public) != 32 or len(private) not in (64, 96) or private[-32:] != public:
    raise SystemExit('Sparkle public and exported private keys do not match.')
if info.get('SUPublicEDKey') != os.environ['UPDATE_PUBLIC_KEY'].strip():
    raise SystemExit('The app must embed the same Sparkle public key.')
tools = list((root / '.build/artifacts').glob('**/bin/sign_update'))
if not tools:
    raise SystemExit('Sparkle signing tool was not found in resolved package artifacts.')
namespace = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', namespace)
archive = root / 'dist/QuotaBar-macOS.zip'
feed = root / 'dist/appcast.xml'
# NamedTemporaryFile creates a private 0600 key file. Never put key material in arguments or logs.
with tempfile.NamedTemporaryFile(mode='w', prefix='quotabar-update-key-', delete=True) as key_file:
    key_file.write(private_string)
    key_file.flush()
    signed = subprocess.run([str(tools[0]), '--ed-key-file', key_file.name, str(archive)],
                            check=True, capture_output=True, text=True).stdout
    match = re.search(r'sparkle:edSignature="([A-Za-z0-9+/=]+)"', signed)
    if not match:
        raise SystemExit('Sparkle did not return an archive signature.')
    signature = match.group(1)
    rss = ET.Element('rss', version='2.0')
    channel = ET.SubElement(rss, 'channel')
    ET.SubElement(channel, 'title').text = 'QuotaBar updates'
    ET.SubElement(channel, 'link').text = 'https://github.com/ar4ft/QuotaBar/releases'
    item = ET.SubElement(channel, 'item')
    ET.SubElement(item, 'title').text = 'QuotaBar ' + info['CFBundleShortVersionString']
    ET.SubElement(item, 'pubDate').text = email.utils.formatdate(usegmt=True)
    ET.SubElement(item, '{' + namespace + '}version').text = info['CFBundleVersion']
    ET.SubElement(item, '{' + namespace + '}shortVersionString').text = info['CFBundleShortVersionString']
    ET.SubElement(item, '{' + namespace + '}minimumSystemVersion').text = info['LSMinimumSystemVersion']
    ET.SubElement(item, 'enclosure', {
        'url': 'https://github.com/ar4ft/QuotaBar/releases/download/' + tag + '/QuotaBar-macOS.zip',
        'length': str(archive.stat().st_size), 'type': 'application/octet-stream',
        '{' + namespace + '}edSignature': signature,
    })
    ET.indent(rss)
    ET.ElementTree(rss).write(feed, encoding='utf-8', xml_declaration=True)
    subprocess.run([str(tools[0]), '--ed-key-file', key_file.name, str(feed)], check=True, capture_output=True)
    subprocess.run([str(tools[0]), '--ed-key-file', key_file.name, '--verify', str(feed)], check=True, capture_output=True)
print('Created signed appcast.xml for ' + tag)
