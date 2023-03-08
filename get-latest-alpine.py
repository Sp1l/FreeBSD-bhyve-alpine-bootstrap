#!/usr/bin/env python3

import urllib.request
import yaml

BASE_URL = "https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64"

with urllib.request.urlopen(f"{BASE_URL}/latest-releases.yaml") as response:
    data = yaml.safe_load(response.read().decode())

iso = [flavor["iso"] for flavor in data if flavor["flavor"] == "alpine-virt"][0]

print(f"{BASE_URL}/{iso}")