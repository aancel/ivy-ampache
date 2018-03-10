;;; ivy-ampache --- A package for listening to music from your ampache instance

;;; Author: Alexandre Ancel
;;; Created: 05/03/2018
;;; URL: https://github.com/aancel/ivy-ampache

;;; Commentary:
;;; Code:

;; * Dependency checks
(if (not (featurep 'cl-lib))
    (error "Package cl-lib not present")
    (require 'cl-lib)
)

(if (not (featurep 'ivy))
    (error "Package ivy not present")
    (require 'ivy)
)

;; * Variables
(defvar ampache-auto-login t
  "Enable/disable auto-login feature to ampache."
)

(defvar ampache-debug nil
  "Enable debug log."
)

(defvar ampache-user ""
    "User name to be used to access the service."
)
(defvar ampache-password ""
    "Password or API Token generated for this application."
)
(defvar ampache-base-url ""
  "Base ampache server url, e.g for Nextcloud/Music https://nextcloud.domain.com/index.php/apps/music/ampache."
)
(defvar ampache-auth-token ""
  "Auth token for the current session."
)
(defvar ampache-result-limit "100"
  "Limit for the number of results of a query."
)

(defvar ampache-media-player ""
  "Media player to use.  Please provide full paths if the command is not available in your environment."
)

(defvar ampache-use-emms-backend nil
  "Use emms backend."
)

;; * Functions

(defun ampache--log (event)
    "Log the EVENT in a log buffer, if debug is enabled."
    (if ampache-debug
        (with-current-buffer (get-buffer-create "*Ampache Debug Log*")
            (goto-char (point-max))
            (insert
                ;; Add 2 new lines
                (concat event "

"
                )
            )
        )
    )
)

(defun ampache--query (url)
    "Query data from an URL, remove the http header and parse the xml."
    (let*
        (
            ;; Query ampache server and remove http header
            (response
                ;; https://emacs.stackexchange.com/questions/12464/go-to-body-after-url-retrieve-synchronously
                (with-current-buffer
                    ;; Get the data from the url
                    (url-retrieve-synchronously url)
                    (goto-char (point-min))
                    ;; Search for the first empty line
                    (re-search-forward "^$")
                    ;; Delete from the start to the empty line (http header)
                    (delete-region (point) (point-min))
                    (buffer-string)
                )
            )

            ;; Parse xml answer
            (xml-text
                (with-temp-buffer
                    (insert response)
                    (xml-parse-region (point-min) (point-max))
                )
            )
        )
        (ampache--log url)
        (ampache--log (format "%s" xml-text))
        ;; Return the parsed xml answer
        xml-text
    )
)

(cl-defun ampache--build-url ( &key (auth nil) (action nil) (user nil) (timestamp nil) (filter nil) (limit nil) )
    "Build an url for the ampache server."
    (let*
        (
            (url
                (concat
                    ampache-base-url
                    "/server/xml.server.php"
                    "?auth="
                    (if auth
                        auth
                        ampache-auth-token
                    )
                    "&user="
                    (if user
                        user
                        ampache-user
                    )
                    (if timestamp
                        (concat "&timestamp=" timestamp)
                    )
                    (if action
                        (concat "&action=" action)
                    )
                    (if (not (string= "" ampache-result-limit))
                        "&limit=" ampache-result-limit
                    )
                    (if filter
                        (concat "&filter=" filter)
                    )
                )
            )
        )
        url
    )
)

(defun ampache--handshake ()
    "Perform handshake with the ampache server."
    (let*
        (
            ;; To build the initial handshake query, see https://github.com/ampache/ampache/wiki/XML-API
            ;; Get Unix time
            (time (truncate (float-time)))
            ;; Build the passphrase
            (passphrase
                (secure-hash 'sha256
                    (concat (number-to-string time) (secure-hash 'sha256 ampache-password))
                )
            )
            ;; Build the handshake url
            (handshake
                (ampache--build-url
                    :auth passphrase
                    :action "handshake"
                    :user ampache-user
                    :timestamp (number-to-string time)
                )
            )
            ;; Query for handshake
            (handshake-response (ampache--query handshake))
        )

        (ampache--log handshake)
        handshake-response
    )
)

(defun ampache--get-auth (xml)
    "Extract the auth token from the <auth> tag in the XML answer."
    (let*
        (
            ;; Extract the auth token from <auth>
            (root (car xml))
            (attrs (xml-node-attributes root))
            (auth (car (xml-get-children root 'auth)))
            (text (car (xml-node-children auth)))
        )
        text
    )
)

(defun ampache--check-error ()
    "Check for errors, by performing a query."
    (let*
        (
            (url (ampache--build-url :action "artists"))
            (xml-text (ampache--query url))

            ;; Extract the auth token from <auth>
            (root (car xml-text))
            (error (car (xml-get-children root 'error)))
            (text (car (xml-node-children error)))
        )
        text
    )
)

(defun ampache--check-connection ()
    "Check if the connection is correctly established."
    (let*
        (
            (connection-ok nil)
            (err nil)
        )
        (setq err (ampache--check-error))
        (if err
            (progn
                (message (concat "Error: " err))
                (ampache--log (concat "Error: " err))

                (if ampache-auto-login
                    (progn
                        (message "Attempting auto-login")
                        (ampache--log "Attempting auto-login")

                        (ampache-authenticate)
                        (setq err (ampache--check-error))
                        (if err
                            (progn
                                (message (concat "Login error (" err ")"))
                                (ampache--log (concat "Login error (" err ")"))
                            )
                            (setq connection-ok t)
                        )
                    )
                )
            )
            (setq connection-ok t)
        )
        connection-ok
    )
)

(defun ampache-authenticate ()
    "Perform the handshake and store the auth token in a variable."
    (interactive)
    (let*
        (
            (handshake-response (ampache--handshake))
            (local-auth-token (ampache--get-auth handshake-response))
        )
        ;; Set up global setup
        (setq ampache-auth-token local-auth-token)
        local-auth-token
    )
)

(defun ampache--filter-artists (filter)
    "Allow to list artists from the server, possibly filtered (via FILTER)."
    (let*
        (
            (url
                (ampache--build-url
                    :action "artists"
                    :filter filter
                )
            )

            (xml (ampache--query url))

            ;; Get the <root> element of the list
            (root (car xml))
            ;; Get all children name <artist>
            (artists (xml-get-children root 'artist))
            (artist ())
            (name "")
            (list1 ())
            (result ())
            (attrs ())
            (id "")
        )
        ;; Iterate over the artist list
        ;; And push their name in the result list
        (dolist (artist artists)
            (progn
                (setq list1 ())

                ;; Get the artist name and id
                (setq name (car (xml-get-children artist 'name)))
                (setq attrs (xml-node-attributes artist))
                (setq id (cdr (assq 'id attrs)))

                ;; Push the artist name and id into a temporary list
                (push (car (xml-node-children name)) list1)
                (push id list1)

                ;; Push the list in the results (on the front)
                (push list1 result)
            )
        )

        ;; We reverse the list because we pushed at the front at each iteration
        (reverse result)
    )
)

(defun ampache--get-artists ()
    "Allow to list all the artists from the server."
    (ampache--filter-artists "")
)

(defun ampache--get-albums-by-artist (artistID)
    "Allow to list album from a specific artist (by uid via ARTISTID)."
    (let*
        (
            ;; Query for albums by artist ID
            (url
                (ampache--build-url
                    :action "artist_albums"
                    :filter artistID
                )
            )

            ;; Send the query to the server
            (xml (ampache--query url))

            ;; Get the <root> element of the list
            (root (car xml))
            ;; Get all children name <artist>
            (albums (xml-get-children root 'album))
            (album ())
            (name "")
            (list1 ())
            (result ())
            (attrs ())
            (id "")
        )
        ;; Iterate over the artist list
        ;; And push their name in the result list
        (dolist (album albums)
            (progn
                (setq list1 ())

                ;; Get the artist name and id
                (setq name (car (xml-get-children album 'name)))
                (setq attrs (xml-node-attributes album))
                (setq id (cdr (assq 'id attrs)))

                ;; Push the artist name and id into a temporary list
                (push (car (xml-node-children name)) list1)
                (push id list1)

                ;; (print id)
                ;; Push the list in the results (on the front)
                (push list1 result)
            )
        )
        ;; Return the sorted list
        ;; (print (sort result 'string<))

        ;; We reverse the list because we pushed at the front at each iteration
        (reverse result)
    )
)

(defun ampache--get-artist-id (name)
    "Get an artist id by its NAME."
    (let*
        (
            (url
                (ampache--build-url
                    :action "artists"
                    :filter name
                )
            )

            (xml (ampache--query url))

            ;; Get the <root> element of the list
            (root (car xml))
            ;; Get all children name <artist>
            (artists (xml-get-children root 'artist))
            (artist ())
            (result ())
            (attrs ())
            (current-name "")
            (id "")
        )
        ;; Get the first artist of the list, it was normally filtered
        (setq artist (car artists))
        ; Get the id attribute
        (setq attrs (xml-node-attributes artist))
        (setq id (cdr (assq 'id attrs)))
    )
)

(defun ampache--get-album-id (name)
    "Get an album id by its NAME."
    (let*
        (
            (url
                (ampache--build-url
                    :action "albums"
                    :filter name
                )
            )

            (xml (ampache--query url))

            ;; Get the <root> element of the list
            (root (car xml))
            ;; Get all children name <album>
            (albums (xml-get-children root 'album))
            (album ())
            (result ())
            (attrs ())
            (current-name "")
            (id "")
        )
        (ampache--log xml)

        ;; Get the first album of the list, it was normally filtered
        (setq album (car albums))
        ; Get the id attribute
        (setq attrs (xml-node-attributes album))
        (setq id (cdr (assq 'id attrs)))
    )
)

(defun ampache--get-album-songs (albumID)
    "Allows to list album from a specific artist (by uid)."
    (let*
        (
            (url
                (ampache--build-url
                    :action "album_songs"
                    :filter albumID
                )
            )

            (xml (ampache--query url))

            ;; Get the <root> element of the list
            (root (car xml))
            ;; Get all children name <artist>
            (songs (xml-get-children root 'song))
            (song ())
            (title "")
            (track "")
            (url "")
            (list1 ())
            (result ())
            (attrs ())
            (id "")
        )
        ;; Iterate over the artist list
        ;; And push their name in the result list
        (dolist (song songs)
            (progn
                (setq list1 ())

                ;; Get the song information, e.g. name and id
                (setq title (car (xml-get-children song 'title)))
                (setq url (car (xml-get-children song 'url)))
                (setq track (car (xml-get-children song 'track)))

                (setq attrs (xml-node-attributes song))
                (setq id (cdr (assq 'id attrs)))

                ;; Push the song name, url and id into a temporary list
                (push (car (xml-node-children url)) list1)
                (push (car (xml-node-children title)) list1)
                (push (car (xml-node-children track)) list1)
                (push id list1)
                ;; Push the list in the results (on the front)
                (push list1 result)
            )
        )
        ;; Return the sorted list
        ;; (print (sort result 'string<))

        ;; We reverse the list because we pushed at the front at each iteration
        (reverse result)
    )
)

(cl-defun ampache--emms-enqueue-song ( &key (artist "Unknown") (album "Unknown") (tracknumber 0) (title "Unknown") (url "") )
    "Enqueue song by URL in EMMS."
    (let*
        (
            (track (emms-track 'url url))
        )
        (ampache--log (concat "Enqueueing " tracknumber " - " artist " - " title))
        (emms-track-set track 'info-tracknumber tracknumber)
        (emms-track-set track 'info-title title)
        (emms-track-set track 'info-artist artist)
        (emms-track-set track 'info-album album)
        (with-current-emms-playlist (emms-playlist-insert-track track))
        ;; (emms-add-url url)
    )
)

(cl-defun ampache--player-enqueue-song ( &key (artist "Unknown") (album "Unknown") (tracknumber 0) (title "Unknown") (url "") )
    "Enqueue song by URL in the media player."
    (let*
        (
            ;; Remove the directory part of the path (Useful especially on Windows)
            (basename (file-name-nondirectory ampache-media-player))
            ;; Remove the extension of the player (Useful especially on Windows)
            (basename-sans-extension (file-name-sans-extension basename))

            (player-command "")
        )
        ;; (print cmd)
        ;; (shell-command-to-string cmd)

        (if (string= ampache-media-player "")
            (error "No media player set.  Please set the 'ampache-media-player' variable")
        )

        (if (not (executable-find ampache-media-player))
            (error "Cannot find media-player.  Please set the 'ampache-media-player' variable")
        )

        (if (string= basename-sans-extension "clementine")
            (progn
                (setq player-command
                    (concat
                        "\"" ampache-media-player "\" "
                        "-a "
                        "\"" url "\""
                    )
                )
            )

            (if (string= basename-sans-extension "vlc")
                (setq player-command
                    (concat
                        "\"" ampache-media-player "\" "
                        "--started-from-file --playlist-enqueue "
                        "--meta-title=\"" title "\" "
                        "--meta-artist=\"" artist "\" "
                        "--meta-description=\"" album "\" "
                        "--meta-url=\"" url "\" "
                        "\"" url "\""
                    )
                )

                (progn
                    (message "This player is unknown. Attempting to play.")
                    (setq player-command
                        ampache-media-player
                        url
                    )
                )
            )
        )
        (ampache--log player-command)
        (start-process-shell-command basename-sans-extension (concat basename-sans-extension "-buffer") player-command)
    )
)

(defun ivy-ampache--select-artist (artists)
    "Use Ivy to select an artist from an ARTISTS list."
    (ivy-read "Artists:" artists)
)

(defun ivy-ampache--select-album (albums)
    "Use Ivy to select an album from an ALBUMS list."
    (ivy-read "Albums:" albums)
)

(defun ivy-ampache-play-album ()
    "Use Ivy to select an album from an ALBUMS list."
    (interactive)
    (let*
        (
            (connection-ok nil)
            (artist "")
            (artist-list ())
            (selected-artist "")
            (artist-id "")

            (album "")
            (album-list ())
            (selected-album "")
            (album-id "")

            (song-list ())
            (song-number "")
            (song-name "")
            (song-url "")
        )

        ;; Check for connection and possibly auto-connect
        (setq connection-ok (ampache--check-connection))

        (if connection-ok
            (progn
                ;; Get Artist list
                (setq artist-list (ampache--get-artists))
                (ampache--log (format "%s" artist-list))
                (ampache--log (format "%s" (mapcar 'cdr artist-list)))

                ;; Filter artists via ivy and extract ID
                ;; Use mapcar to only extract artist names
                (setq selected-artist (ivy-ampache--select-artist (mapcar 'cdr artist-list)))
                (ampache--log (format "%s" selected-artist))
                (dolist (artist artist-list)
                    (progn
                        (if (string= selected-artist (car (cdr artist)))
                            (setq artist-id (car artist))
                        )
                    )
                )
                (ampache--log (format "%s" artist-id))

                ;; Get albums of the current artist
                (setq album-list (ampache--get-albums-by-artist artist-id))
                (ampache--log (format "%s" album-list))
                (ampache--log (format "%s" (mapcar 'cdr album-list)))

                ;; Filter albums via ivy and extract ID
                ;; Use mapcar to only extract album names
                (setq selected-album (ivy-ampache--select-album (mapcar 'cdr album-list)))
                (ampache--log selected-album)
                (dolist (album album-list)
                    (progn
                        (if (string= selected-album (car (cdr album)))
                            (setq album-id (car album))
                        )
                    )
                )
                (ampache--log (format "%s" album-id))

                ;; Get the songs of the selected album
                (setq song-list (ampache--get-album-songs album-id))

                ;; Enqueue the songs of the album
                (ampache--log (format "%s" song-list))
                (dolist (song song-list)
                    (progn
                        (setq song-number (car (cdr song)))
                        (setq song-name (car (cdr (cdr song))))
                        (setq song-url (car (cdr (cdr (cdr song)))))
                        (if ampache-use-emms-backend
                            (ampache--emms-enqueue-song
                                :artist selected-artist
                                :album selected-album
                                :tracknumber song-number
                                :title song-name
                                :url song-url
                            )
                            (ampache--player-enqueue-song
                                :artist selected-artist
                                :album selected-album
                                :tracknumber song-number
                                :title song-name
                                :url song-url
                            )
                        )
                    )
                )
            )
        )
    )
)

(provide 'ivy-ampache)
;;; ivy-ampache ends here
