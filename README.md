This repo is no longer useful since the virtual text feature was introduced by the Vim patch [9.0.0067](https://github.com/vim/vim/releases/tag/v9.0.0067).  See [`:help virtual-text`](https://vimhelp.org/textprop.txt.html#virtual-text).

---

Work in progress.  Bugs to fix; features to implement; doc to write.

To test:

    $ git clone https://github.com/lacygoill/vim-virtual-text
    $ vim -Nu NONE +'set rtp=vim-virtual-text' -S vim-virtual-text/test/setup.vim
