#!/bin/ash

file=/tmp/lastupload

# CGI output must start with at least empty line (or headers)
printf '\r\n'
  cat <<EOF
<html>
<head>
<title>Upload</title>
<meta http-equiv="Content-Type" content="text/html; charset=iso-8859-1" />
</head>
<body>
EOF

IFS=$'\r'
read -r delim_line

IFS=''
delim_line="${delim_line}--"$'\r'

read -r line
filename=$(echo $line | sed 's/^.*filename=//' | sed 's/\"//g' | sed 's/.$//')
fileext=${filename##*.}

while read -r line; do
    test "$line" = '' && break
    test "$line" = $'\r' && break
done

# Note: This will result in junk at end of line (see format above)
cat > $file

# Get the line count
LINES=$(wc -l $file | cut -d ' ' -f 1)

# Remove the last line
head -$((LINES - 1)) $file >$file.1

# Copy eveything but the last line to a temp file
head -$((LINES - 2)) $file.1 >$file.2

# Copy the new last line but remove trailing \r\n
tail -1 $file.1 > $file.3
tail -c 2 $file.3 > $file.5
CRLF=$(hexdump -ve '/1 "%.2x"' $file.5)
# Check if the last two bytes are \r\n
if [ "$CRLF" = "0d0a" ];then
   BYTES=$(wc -c $file.3 | cut -d ' ' -f 1)
   truncate -s $((BYTES-2)) $file.3
fi

rm $file.5
cat $file.2 $file.3 > $file.4
cp $file.4 $file

cat <<EOF
<h1>Upload Successful</h1>
EOF

cat <<EOF
</body>
</html>
EOF

exit 0