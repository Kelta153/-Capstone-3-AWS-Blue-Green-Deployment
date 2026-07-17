#!/bin/bash

yum update -y
yum install -y httpd

systemctl enable httpd
systemctl start httpd

cat <<EOF > /var/www/html/index.html
<!DOCTYPE html>
<html>
<head>
<title>Green Environment</title>
<style>
body{
font-family:Arial,sans-serif;
background:#198754;
color:white;
text-align:center;
padding-top:100px;
}
.card{
background:white;
color:#333;
display:inline-block;
padding:30px;
border-radius:10px;
box-shadow:0 0 10px rgba(0,0,0,.3);
}
h1{
color:#198754;
}
</style>
</head>
<body>

<div class="card">
<h1>Safaricom Telecom Portal</h1>

<h2>GREEN Environment</h2>

<p>Version 2.0</p>

<p>Status: Candidate Release</p>

<p>Blue-Green Deployment Capstone</p>

</div>

</body>
</html>
EOF