# `ivy-ampache`

`ivy-ampache` is an elisp package allowing you to access your [ampache](https://github.com/ampache/ampache) library from Emacs.    
It uses the [XML API](https://github.com/ampache/ampache/wiki/XML-API) of [ampache](https://github.com/ampache/ampache) to get the data from the server.    
It parses artists, albums, songs and the streaming url. The urls are then fed to an external player for audio playback.

It currently can use several players as backends. Please refer to the related section.

The main entrypoint function is `ivy-ampache-play-album`.

This package has only been tested with the [music](https://github.com/owncloud/music) application and [Nextcloud](https://github.com/nextcloud), but it *should* work with a traditional ampache server.

**Diclaimer**: This is my first Emacs and elisp package, so there might be dragons. Furthermore, don't hesitate to provide feedback and advices to improve the code quality (as I am mainly an object-oriented programmer).

The package has been tested on GNU Linux (Ubuntu) and Windows.

## Installation

Via el-get (or other package managers that handle github urls):

``` emacs-lisp
(el-get-bundle ivy-ampache
    :url "https://github.com/aancel/ivy-ampache"
    :features ivy-ampache)
```

## Configuration

### General information
- Setup the environment for the package

``` emacs-lisp
;; Login information
(setq ampache-user "user")
(setq ampache-password "password")

;; Url of the instance
(setq ampache-base-url "https://nextcloud.domain.com/index.php/apps/music/ampache")
(setq ampache-result-limit "100")
```

#### Music application for Nextcloud

If you use the [music](https://github.com/owncloud/music) application for [Nextcloud](https://github.com/nextcloud),
the auth parameters you have to provide are your username and an API password that you can generate in Settings > Additional settings.

### Player backends

As of now, there are two backend for playing music and handling playlists:
- Either via emms, by setting:

``` emacs-lisp
;; When using this backend on Windows, use mplayer instead of vlc
;; Using the external vlc process tends to block further accesses to the server
(setq ampache-use-emms-backend t)
```

- Or directly via external players

``` emacs-lisp
;; Do not use the emms backend
(setq ampache-use-emms-backend nil)

;; Then specify the media player path
(setq ampache-media-player "C:\\Program Files (x86)\\Clementine\\clementine.exe")

```

[Clementine](https://github.com/clementine-player/Clementine) and [vlc](https://github.com/videolan/vlc) are available,
other players could be supported.


### Auto-login
- Make sure ampache-auto-login is enabled

``` emacs-lisp
;; Sets up auto-login to instance, otherwise use (ampache-authenticate)
(setq ampache-auto-login t)
```

- Enqueue albums

``` emacs-lisp
M-x ivy-ampache-play-album
```

### Manual login
- Authenticate with your server

``` emacs-lisp
M-x ampache-authenticate
```

- Enqueue albums

``` emacs-lisp
M-x ivy-ampache-play-album
```

