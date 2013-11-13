TracePing
=========

TracePing is a mod for smokeping that adds traceroute output to the output for a node.

  - TracePing uses it's own daemon for collecting information
  - TracePing uses a (very simple) SQL backend for storing data
  - TracePing is a bit of a hack.

Installation
--------------

Copy traceping.cgi to live along side smokeping.cgi & chmod 0755

```
cp smokeping.cgi /usr/lib/cgi-bin/traceping.cgi
chmod 0755 /usr/lib/cgi-bin/traceping.cgi
```

Add traceping as a ScriptAlias to apache config (should probably be next to the ScriptAlias for smokeping):

```
ScriptAlias /smokeping/traceping.cgi /usr/lib/cgi-bin/traceping.cgi

```


Copy basehtml.html and overwrite the provided one with the modified version


```
cp /etc/smokeping/basehtml.html /etc/smokeping/basehtml.html.bak
cp basehtml.html /etc/smokeping/basehtml
```

Create the sqlite database and import the dump

```
sqlite3 test.sqlite < schema.sqlite
```

Edit the $dsn variables in traceping.cgi and traceping_daemon.pl to match your databases.

Install the POE perl module (may exist in OS repos!)

```
cpan POE
```

License
--------------

Licensed under a BSD license
```

Development funded by [Rack911](http://rack911.com)
