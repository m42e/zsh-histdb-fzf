**NB:** If you like this, you might want to have an implementation with a better performance: [zsh-histdb-skim](https://github.com/m42e/zsh-histdb-skim)

zsh-histdb-fzf
==============

This addon uses fzf for searching the history kept with [zsh-histdb](https://github.com/larkery/zsh-histdb).

See the example here:

[![asciicast](https://asciinema.org/a/oRYb505aRW8exHWI6tzYPw0ww.svg)](https://asciinema.org/a/oRYb505aRW8exHWI6tzYPw0ww)


Activation
----------

To enable the widget add the following binding to you zshrc

```zsh
bindkey '^R' histdb-fzf-widget
```

Configuration
-------------

- Date format: By default, the date format (`us` or `non-us`) is auto-detected based on your current locale settings
  (see `LC_TIME`). You can override this by setting the environment variable `HISTDB_FZF_FORCE_DATE_FORMAT` to either
  `us` or `non-us`.

Logging
-------

If a filename is set to `HISTDB_FZF_LOGFILE` some debug information will be appended to that file.
