#!/usr/bin/env fish
echo "📦 Last 200 installed packages on Fedora:"
rpm -qa --qf '%{installtime:date}\t%{name}-%{version}\n' | sort | tail -200 | nl
