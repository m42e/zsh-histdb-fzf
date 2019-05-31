zsh-histdb-fzf
==============

This addon uses fzf for searching the history kept with [zsh-histdb](https://github.com/larkery/zsh-histdb).

See the example here:

[![asciicast](https://asciinema.org/a/oRYb505aRW8exHWI6tzYPw0ww.svg)](https://asciinema.org/a/oRYb505aRW8exHWI6tzYPw0ww)


At the moment there is no configuration, besides changing the code.


Activation
----------  

To enable the widget add the following binding to you zshrc

```zsh
zle     -N   histdb-fzf-widget
bindkey '^R' histdb-fzf-widget
```

