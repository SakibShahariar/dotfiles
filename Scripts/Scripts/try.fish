#!/usr/bin/env fish


# Set up mirrors close to Bangladesh and globally for testing
set mirrors "https://mirrors.tuna.tsinghua.edu.cn/fedora/releases/\$releasever/Everything/\$basearch/os/"
set mirrors $mirrors "http://mirror.iitb.ac.in/fedora/releases/\$releasever/Everything/\$basearch/os/"
set mirrors $mirrors "https://mirror.sjtu.edu.cn/fedora/releases/\$releasever/Everything/\$basearch/os/"
set mirrors $mirrors "https://mirrors.fedoraproject.org/metalink?repo=fedora-\$releasever&arch=\$basearch"
set mirrors $mirrors "https://mirror.mit.edu/fedora/releases/\$releasever/Everything/\$basearch/os/"
set mirrors $mirrors "https://mirror.ucsc.edu/fedora/releases/\$releasever/Everything/\$basearch/os/"
set mirrors $mirrors "https://mirror.hkg.fr/fedora/releases/\$releasever/Everything/\$basearch/os/"
set mirrors $mirrors "http://mirror.bangladesh.edu/fedora/releases/\$releasever/Everything/\$basearch/os/"
set mirrors $mirrors "https://mirror.math.princeton.edu/pub/fedora/releases/\$releasever/Everything/\$basearch/os/"
set mirrors $mirrors "http://mirror.rackspace.com/fedora/releases/\$releasever/Everything/\$basearch/os/"
set mirrors $mirrors "https://mirror.pit.teraswitch.com/fedora/releases/\$releasever/Everything/\$basearch/os/"
set mirrors $mirrors "https://mirror.leaseweb.com/fedora/releases/\$releasever/Everything/\$basearch/os/"
set mirrors $mirrors "https://mirror.nl.leaseweb.net/fedora/releases/\$releasever/Everything/\$basearch/os/"
set mirrors $mirrors "http://mirror.centos.org/fedora/releases/\$releasever/Everything/\$basearch/os/"
set mirrors $mirrors "https://mirror.yandex.ru/fedora/releases/\$releasever/Everything/\$basearch/os/"
set mirrors $mirrors "http://mirror.centos.org/fedora/releases/\$releasever/Everything/\$basearch/os/"
set mirrors $mirrors "http://mirror.rackspace.com/fedora/releases/\$releasever/Everything/\$basearch/os/"
set mirrors $mirrors "https://mirror.bicp.net/fedora/releases/\$releasever/Everything/\$basearch/os/"

# Test each mirror by downloading from it and measuring time
for mirror in $mirrors
    echo -n "Testing $mirror → "
    curl -o /dev/null -s -w "%{time_total}s\n" --connect-timeout 2 $mirror
end

