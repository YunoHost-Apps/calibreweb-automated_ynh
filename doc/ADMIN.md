* By default, removing the app will **not** delete the library, unless you remove the app with the --purge option.

* Default library directory is __DATA_DIR__/eBook. You may change it to any path you want (e.g. if you have already a Calibre Library in another location - the chosen directory must already contain a [metadata.db](https://github.com/crocodilestick/Calibre-Web-Automated/blob/main/empty_library/metadata.db) file). To change the directory, go to <https://__DOMAIN__/yunohost/admin/#/apps/__APP__/main>.

* Authorization access to library to be done manually after install if Calibre library was already existing (except in yunohost.multimedia directory), for example :
```
chown -R __APP__: path/to/library
or
chmod o+rw path/to/library
```

* When you add a book from the web interface, you have to "Refresh Library" to take the new book into account. There is currently no watching option in this package. 