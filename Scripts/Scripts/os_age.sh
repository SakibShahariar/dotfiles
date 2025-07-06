#!/bin/bash

# Get root filesystem birth date in seconds since epoch
birth_date=$(stat -c %W /)

# Get current date in seconds since epoch
current_date=$(date +%s)

# Calculate difference in seconds
diff_sec=$((current_date - birth_date))

# Convert seconds to days
diff_days=$((diff_sec / 86400))

# Calculate months and days approximately
months=$((diff_days / 30))
days=$((diff_days % 30))

echo "${months} months and ${days} days"
