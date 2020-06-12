;;; helm-files.el --- helm file browser and related. -*- lexical-binding: t -*-

;; Copyright (C) 2012 ~ 2019 Thierry Volpiatto <thierry.volpiatto@gmail.com>

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Code:

(require 'cl-lib)
(require 'helm)
(require 'helm-types)
(require 'helm-utils)
(require 'helm-grep)
(require 'helm-help)
(require 'helm-locate)
(require 'helm-tags)
(require 'helm-buffers)
(eval-when-compile
  (require 'thingatpt)
  (require 'ffap)
  (require 'dired-aux)
  (require 'dired-x)
  (require 'tramp)
  (require 'image-dired))

(declare-function find-library-name "find-func.el" (library))
(declare-function w32-shell-execute "ext:w32fns.c" (operation document &optional parameters show-flag))
(declare-function gnus-dired-attach "ext:gnus-dired.el" (files-to-attach))
(declare-function image-dired-display-image "image-dired.el" (file &optional original-size))
(declare-function image-dired-update-property "image-dired.el" (prop value))
(declare-function eshell-read-aliases-list "em-alias")
(declare-function eshell-send-input "esh-mode" (&optional use-region queue-p no-newline))
(declare-function eshell-kill-input "esh-mode")
(declare-function eshell-bol "esh-mode")
(declare-function eshell-reset "esh-mode.el")
(declare-function eshell/cd "em-dirs.el")
(declare-function eshell-next-prompt "em-prompt.el")
(declare-function helm-ls-git-ls "ext:helm-ls-git")
(declare-function helm-hg-find-files-in-project "ext:helm-ls-hg")
(declare-function helm-gid "helm-id-utils.el")
(declare-function helm-find-1 "helm-find")
(declare-function helm-get-default-program-for-file "helm-external")
(declare-function helm-open-file-externally "helm-external")
(declare-function term-line-mode "term")
(declare-function term-char-mode "term")
(declare-function term-send-input "term")
(declare-function term-next-prompt "term")
(declare-function term-process-mark "term")

(defvar term-char-mode-point-at-process-mark)
(defvar term-char-mode-buffer-read-only)
(defvar recentf-list)
(defvar helm-mm-matching-method)
(defvar dired-async-mode)
(defvar org-directory)

(defgroup helm-files nil
  "Files applications and libraries for Helm."
  :group 'helm)

(defcustom helm-tramp-verbose 0
  "Just like `tramp-verbose' but specific to Helm.
When set to 0 don't show tramp messages in Helm.
If you want to have the default tramp messages set it to 3."
  :type 'integer
  :group 'helm-files)

(defcustom helm-ff-auto-update-initial-value nil
  "Auto update when only one candidate directory is matched.
Default value when starting `helm-find-files' is nil to not
confuse new users.
For a better experience with `helm-find-files' set this to
non-nil and use C-<backspace> to toggle it."
  :group 'helm-files
  :type  'boolean)

(defcustom helm-ff-history-max-length 100
  "Number of elements shown in `helm-find-files' history."
  :group 'helm-files
  :type 'integer)

(defcustom helm-ff-fuzzy-matching t
  "Enable fuzzy matching for `helm-find-files' when non--nil.
See `helm-ff--transform-pattern-for-completion' for more info."
  :group 'helm-files
  :type 'boolean)

(defcustom helm-ff-exif-data-program "exiftran"
  "Program used to extract exif data of an image file."
  :group 'helm-files
  :type 'string)

(defcustom helm-ff-exif-data-program-args "-d"
  "Arguments used for `helm-ff-exif-data-program'."
  :group 'helm-files
  :type 'string)

(defcustom helm-ff-newfile-prompt-p t
  "Whether Prompt or not when creating new file.
This set `ffap-newfile-prompt'."
  :type  'boolean
  :group 'helm-files)

(defcustom helm-ff-avfs-directory "~/.avfs"
  "The default avfs directory, usually '~/.avfs'.
When this is set you will be able to expand archive filenames
with `C-j' inside an avfs directory mounted with mountavfs.
See <http://sourceforge.net/projects/avf/>."
  :type  'string
  :group 'helm-files)

(defcustom helm-ff-file-compressed-list '("gz" "bz2" "zip" "7z")
  "Minimal list of compressed files extension."
  :type  '(repeat (choice string))
  :group 'helm-files)

(defcustom helm-ff-printer-list nil
  "A list of available printers on your system.
When non-nil let you choose a printer to print file.
Otherwise when nil the variable `printer-name' will be used.
On Unix based systems (lpstat command needed) you don't need to
set this, `helm-ff-find-printers' will find a list of available
printers for you."
  :type '(repeat (choice string))
  :group 'helm-files)

(defcustom helm-ff-transformer-show-only-basename t
  "Show only basename of candidates in `helm-find-files'.
This can be toggled at anytime from `helm-find-files' with \
\\<helm-find-files-map>\\[helm-ff-run-toggle-basename]."
  :type 'boolean
  :group 'helm-files)

(defcustom helm-ff-signal-error-on-dot-files t
  "Signal error when file is `.' or `..' on file deletion when non-nil.
Default is non-nil.
WARNING: Setting this to nil is unsafe and can cause deletion of
a whole tree."
  :group 'helm-files
  :type  'boolean)

(defcustom helm-ff-search-library-in-sexp nil
  "Search for library in `require' and `declare-function' sexp."
  :group 'helm-files
  :type  'boolean)

(defcustom helm-tooltip-hide-delay 25
  "Hide tooltips automatically after this many seconds."
  :group 'helm-files
  :type 'integer)

(defcustom helm-ff-file-name-history-use-recentf nil
  "Use `recentf-list' instead of `file-name-history' in `helm-find-files'."
  :group 'helm-files
  :type 'boolean)

(defcustom helm-ff-skip-boring-files nil
  "Non-nil to skip boring files.
I.e. the files matching regexps in `helm-boring-file-regexp-list'.
This takes effect in `helm-find-files' and file completion used by
`helm-mode' i.e. `helm-read-file-name'.
Note that when non-nil this will slow down slightly `helm-find-files'."
  :group 'helm-files
  :type  'boolean)

(defcustom helm-ff-skip-git-ignored-files nil
  "Non-nil to skip git ignored files.
This take effect only in `helm-find-files'.
Check is not done on remote files.
Note that when non-nil this will slow down slightly
`helm-find-files'."
  :group 'helm-files
  :type 'boolean)

(defcustom helm-ff-candidate-number-limit 5000
  "The `helm-candidate-number-limit' for `helm-find-files' and friends.
Note that when going one level up with
`\\<helm-find-files-map>\\[helm-find-files-up-one-level]' the
length of directory will be used instead if it is higher than
this value.  This is to avoid failing to preselect the previous
directory/file if this one is situated lower than
`helm-ff-candidate-number-limit' num candidate."
  :group 'helm-files
  :type 'integer)

(defcustom helm-ff-up-one-level-preselect t
  "Always preselect previous directory when going one level up.

When non-nil `candidate-number-limit' source value is modified
dynamically when going one level up if the position of previous
candidate in its directory is > to
`helm-ff-candidate-number-limit'.

It can be helpful to disable this and reduce
`helm-ff-candidate-number-limit' if you often navigate across
very large directories."
  :group 'helm-files
  :type 'boolean)

(defcustom helm-files-save-history-extra-sources
  '("Find" "Locate" "Recentf"
    "Files from Current Directory" "File Cache")
  "Extras source that save candidate to `file-name-history'."
  :group 'helm-files
  :type '(repeat (choice string)))

(defcustom helm-find-files-before-init-hook nil
  "Hook that run before initialization of `helm-find-files'."
  :group 'helm-files
  :type 'hook)

(defcustom helm-find-files-after-init-hook nil
  "Hook that run after initialization of `helm-find-files'."
  :group 'helm-files
  :type 'hook)

(defcustom helm-find-files-bookmark-prefix "Helm-find-files: "
  "bookmark name prefix of `helm-find-files' sessions."
  :group 'helm-files
  :type 'string)

(defcustom helm-ff-guess-ffap-filenames nil
  "Use ffap to guess local filenames at point in `helm-find-files'.
This doesn't disable url or mail at point, see
`helm-ff-guess-ffap-urls' for this."
  :group 'helm-files
  :type 'boolean)

(defcustom helm-ff-guess-ffap-urls t
  "Use ffap to guess local urls at point in `helm-find-files'.
This doesn't disable guessing filenames at point, see
`helm-ff-guess-ffap-filenames' for this.
See also `ffap-url-unwrap-remote' that may override this
variable."
  :group 'helm-files
  :type 'boolean)

(defcustom helm-ff-no-preselect nil
  "When non-nil `helm-find-files' starts at root of current directory."
  :group 'helm-files
  :type 'boolean)

(defcustom helm-ff-allow-non-existing-file-at-point nil
  "Use file-at-point as initial input in `helm-find-files' even if it doesn't exists."
  :group 'helm-files
  :type 'boolean)

(defcustom helm-find-files-ignore-thing-at-point nil
  "Use only `default-directory' as default input in `helm-find-files'.
I.e. text under cursor in `current-buffer' is ignored.
Note that when non-nil you will be unable to complete filename at
point in `current-buffer'."
  :group 'helm-files
  :type 'boolean)

(defcustom helm-substitute-in-filename-stay-on-remote nil
  "Don't switch back to local filesystem when expanding pattern with / or ~/."
  :group 'helm-files
  :type 'boolean)

(defcustom helm-ff-goto-first-real-dired-exceptions '(dired-goto-file)
  "Dired commands that are allowed moving to first real candidate."
  :group 'helm-files
  :type '(repeat (choice symbol)))

(defcustom helm-mounted-network-directories nil
  "A list of directories used for mounting remotes filesystem.

When nil `helm-file-on-mounted-network-p' always return nil
otherwise check if a file is in one of these directories.

Remote filesystem are generally mounted with sshfs."
  :group 'helm-files
  :type '(repeat string))

(defcustom helm-browse-project-default-find-files-fn
  (cond ((executable-find "rg")
         #'helm-browse-project-rg-find-files)
        ((executable-find "ag")
         #'helm-browse-project-ag-find-files)
        (t #'helm-browse-project-walk-directory))
  "The default function to retrieve files in a non-vc directory.

A function that takes a directory name as only arg."
  :group 'helm-files
  :type 'function)

(defcustom helm-ff-kill-or-find-buffer-fname-fn
  #'helm-ff-kill-or-find-buffer-fname
  "Default function used to expand non-directory filenames in `helm-find-files'.

This variable will take effect only in `helm-find-files'.  It
affects the behavior of persistent-action on filenames and
non-existing filenames.

The default is to expand filename on first hit on
\\<helm-map>\\[helm-execute-persistent-action], pop buffer in
other window on second hit and finally kill this buffer on third
hit.  This is very handy to create several new buffers, or when
navigating, show quickly the buffer of file to see its contents
briefly before killing it and continue navigating.

However some users may not want this, so to disable this behaviour
just set this to `ignore' function.

Of course you can also write your own function to do something
else."
  :group 'helm-files
  :type 'function)

(defcustom helm-modes-using-escaped-strings
  '(eshell-mode shell-mode term-mode)
  "Modes that requires string's insertion to be escaped."
  :group 'helm-files
  :type '(repeat symbol))

(defcustom helm-ff-allow-recursive-deletes nil
  "When 'always don't prompt for recursive deletion of directories.
When nil, will ask for recursive deletion.
Note that when deleting multiple directories you can answer !
when prompted to avoid being asked for next directories, so it
is probably better to not modify this variable."
  :group 'helm-files
  :type '(choice
          (const :tag "Delete non-empty directories" t)
          (const :tag "Confirm for each directory" nil)))

(defcustom helm-ff-delete-files-function #'helm-delete-marked-files
  "The function to use by default to delete files.

Default is to delete files synchronously, other choice is to
delete files asynchronously.

BE AWARE that when deleting async you will not be warned about
recursive deletion of directories, IOW non-empty directories will
be deleted with no warnings in background!!!

It is the function that will be used when using
`\\<helm-find-files-map>\\[helm-ff-run-delete-file]' from
`helm-find-files'."
  :group 'helm-files
  :type '(choice (function :tag "Delete files synchronously."
                  helm-delete-marked-files)
                 (function :tag "Delete files asynchronously."
                  helm-delete-marked-files-async)))

(defcustom helm-trash-remote-files nil
  "Allow trashing remote files when non-nil.

Trashing remote files with tramp doesn't work out of the box
unless the 'trash-cli' package is installed.  This is why trashing
remote files from Helm is disabled by default.

Tramp is using external 'trash' command in its `delete-file' and
`delete-directory' handlers when using
`delete-by-moving-to-trash', which is documented nowhere in
Emacs.

If you want to enable this you will have to install the 'trash'
command on remote (and/or locally if you want to trash as root).
On Ubuntu-based distributions it is 'trash-cli'."
  :group 'helm-files
  :type 'boolean)

(defcustom helm-list-directory-function
  (cl-case system-type
    (gnu/linux #'helm-list-dir-external)
    (berkeley-unix #'helm-list-dir-lisp)
    (windows-nt #'helm-list-dir-lisp)
    (t #'helm-list-dir-lisp))
  "The function used in `helm-find-files' to list remote directories.

Actually Helm provides two functions to do this:
`helm-list-dir-lisp' and `helm-list-dir-external'.

Using `helm-list-dir-external' will provide a similar display to
what is provided with local files i.e. colorized symlinks,
executables files etc., whereas using `helm-list-dir-lisp' will
allow colorizing only directories but it is more portable.

NOTE: `helm-list-dir-external' needs ls and awk as dependencies.
Also the ls version installed on the remote side should support
the same arguments as the GNU/ls version, which are -A -1 -F -b
and -Q.  So even if you are using a GNU/ls version locally and you
want to connect e.g. on a Freebsd server, you may have failures
due to the incompatible ls version installed on remote server.  In
such case use `helm-list-dir-lisp' which works everywhere but is
slower and less featured (only directories colorized)."
  :type 'function
  :group 'helm-files)

(defcustom helm-ff-initial-sort-method nil
  "Sort method to use when initially listing a directory.
Note that this doesn't affect the listing when matching inside
the directory (i.e. filenames)."
  :group 'helm-files
  :type '(choice
          (const :tag "alphabetically" nil)
          (const :tag "newest" newest)
          (const :tag "size" size)))

(defcustom helm-ff-rotate-image-program "exiftran"
  "External program used to rotate images."
  :group 'helm-files
  :type '(choice
          (const :tag "Mogrify" "mogrify")
          (const :tag "Exiftran" "exiftran")
          (const :tag "Jpegtran" "jpegtran")))

(defcustom helm-ff-rotate-image-switch '("-i")
  "Options used with `helm-ff-rotate-image-program'.
If you are using Mogrify or Jpegtran mandatory option is
\"-rotate\", with Exiftran mandatory option is \"-i\"."
  :group 'helm-files
  :type '(repeat string))

(defcustom helm-ff-use-dir-locals nil
  "Whether to obey dir locals var in helm-find-files.
This allows using for example different values for boring files/dirs
in different directories."
  :group 'helm-files
  :type 'boolean)

(defcustom helm-ff-preferred-shell-mode 'eshell-mode
  "Shell to use to switch to a shell buffer from `helm-find-files'.
Possible values are `shell-mode', `eshell-mode' and `term-mode'.
This affects `\\<helm-find-files-map>\\[helm-ff-run-switch-to-shell]' keybinding."
  :group 'helm-files
  :type '(choice
          (const :tag "Use Eshell" eshell-mode)
          (const :tag "Use Shell" shell-mode)
          (const :tag "Use Shell" term-mode)))

;;; Faces
;;
;;
(defgroup helm-files-faces nil
  "Customize the appearance of helm-files."
  :prefix "helm-"
  :group 'helm-files
  :group 'helm-faces)

(defface helm-ff-prefix
    '((t (:background "yellow" :foreground "black")))
  "Face used to prefix new file or url paths in `helm-find-files'."
  :group 'helm-files-faces)

(defface helm-ff-executable
    '((t (:foreground "green")))
  "Face used for executable files in `helm-find-files'."
  :group 'helm-files-faces)

(defface helm-ff-suid
    '((t (:background "red" :foreground "white")))
  "Face used for suid files in `helm-find-files'."
  :group 'helm-files-faces)

(defface helm-ff-directory
    '((t (:foreground "DarkRed" :background "LightGray")))
  "Face used for directories in `helm-find-files'."
  :group 'helm-files-faces)

(defface helm-ff-dotted-directory
    '((t (:foreground "black" :background "DimGray")))
  "Face used for dotted directories in `helm-find-files'."
  :group 'helm-files-faces)

(defface helm-ff-dotted-symlink-directory
    '((t (:foreground "DarkOrange" :background "DimGray")))
  "Face used for dotted symlinked directories in `helm-find-files'."
  :group 'helm-files-faces)

(defface helm-ff-symlink
    '((t :inherit font-lock-comment-face))
  "Face used for symlinks in `helm-find-files'."
  :group 'helm-files-faces)

(defface helm-ff-invalid-symlink
    '((t (:foreground "black" :background "red")))
  "Face used for invalid symlinks in `helm-find-files'."
  :group 'helm-files-faces)

(defface helm-ff-denied
    '((t (:foreground "red" :background "black")))
  "Face used for non accessible files in `helm-find-files'."
  :group 'helm-files-faces)

(defface helm-ff-file
    '((t (:inherit font-lock-builtin-face)))
  "Face used for file names in `helm-find-files'."
  :group 'helm-files-faces)

(defface helm-ff-truename
    '((t (:inherit font-lock-string-face)))
  "Face used for symlink truenames in `helm-find-files'."
  :group 'helm-files-faces)

(defface helm-ff-dirs
    '((t (:inherit font-lock-function-name-face)))
  "Face used for file names in recursive dirs completion in `helm-find-files'."
  :group 'helm-files-faces)

(defface helm-ff-socket
    '((t (:foreground "DeepPink")))
  "Face used for socket files in `helm-find-files'."
  :group 'helm-files-faces)

(defface helm-ff-pipe
    '((t (:foreground "yellow" :background "black")))
  "Face used for named pipes and character device files in `helm-find-files'."
  :group 'helm-files-faces)

(defface helm-history-deleted
    '((t (:inherit helm-ff-invalid-symlink)))
  "Face used for deleted files in `file-name-history'."
  :group 'helm-files-faces)

(defface helm-history-remote
    '((t (:foreground "Indianred1")))
  "Face used for remote files in `file-name-history'."
  :group 'helm-files-faces)

(defface helm-delete-async-message
    '((t (:foreground "yellow")))
  "Face used for mode-line message."
  :group 'helm-files-faces)

;;; Helm-find-files - The helm file browser.
;;
;; Keymaps

(defvar helm-find-files-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map helm-map)
    (define-key map (kbd "RET")           'helm-ff-RET)
    (define-key map (kbd "C-]")           'helm-ff-run-toggle-basename)
    (define-key map (kbd "C-x C-f")       'helm-ff-run-locate)
    (define-key map (kbd "C-x C-d")       'helm-ff-run-browse-project)
    (define-key map (kbd "C-x r m")       'helm-ff-bookmark-set)
    (define-key map (kbd "C-x r b")       'helm-find-files-switch-to-bookmark)
    (define-key map (kbd "C-x C-q")       'helm-ff-run-marked-files-in-dired)
    (define-key map (kbd "C-s")           'helm-ff-run-grep)
    (define-key map (kbd "M-g s")         'helm-ff-run-grep)
    (define-key map (kbd "M-g p")         'helm-ff-run-pdfgrep)
    (define-key map (kbd "M-g z")         'helm-ff-run-zgrep)
    (define-key map (kbd "M-g a")         'helm-ff-run-grep-ag)
    (define-key map (kbd "M-g g")         'helm-ff-run-git-grep)
    (define-key map (kbd "M-g i")         'helm-ff-run-gid)
    (define-key map (kbd "M-.")           'helm-ff-run-etags)
    (define-key map (kbd "M-R")           'helm-ff-run-rename-file)
    (define-key map (kbd "M-C")           'helm-ff-run-copy-file)
    (when (executable-find "rsync")
      (define-key map (kbd "M-V")         'helm-ff-run-rsync-file))
    (define-key map (kbd "M-B")           'helm-ff-run-byte-compile-file)
    (define-key map (kbd "M-L")           'helm-ff-run-load-file)
    (define-key map (kbd "M-S")           'helm-ff-run-symlink-file)
    (define-key map (kbd "M-Y")           'helm-ff-run-relsymlink-file)
    (define-key map (kbd "M-H")           'helm-ff-run-hardlink-file)
    (define-key map (kbd "M-D")           'helm-ff-run-delete-file)
    (define-key map (kbd "M-K")           'helm-ff-run-kill-buffer-persistent)
    (define-key map (kbd "M-T")           'helm-ff-run-touch-files)
    (define-key map (kbd "C-c d")         'helm-ff-persistent-delete)
    (define-key map (kbd "M-e")           'helm-ff-run-switch-to-shell)
    (define-key map (kbd "C-c i")         'helm-ff-run-complete-fn-at-point)
    (define-key map (kbd "C-c o")         'helm-ff-run-switch-other-window)
    (define-key map (kbd "C-c C-o")       'helm-ff-run-switch-other-frame)
    (define-key map (kbd "C-c C-x")       'helm-ff-run-open-file-externally)
    (define-key map (kbd "C-c C-v")       'helm-ff-run-preview-file-externally)
    (define-key map (kbd "C-c X")         'helm-ff-run-open-file-with-default-tool)
    (define-key map (kbd "M-!")           'helm-ff-run-eshell-command-on-file)
    (define-key map (kbd "M-@")           'helm-ff-run-query-replace-fnames-on-marked)
    (define-key map (kbd "M-%")           'helm-ff-run-query-replace)
    (define-key map (kbd "C-M-%")         'helm-ff-run-query-replace-regexp)
    (define-key map (kbd "C-c =")         'helm-ff-run-ediff-file)
    (define-key map (kbd "M-=")           'helm-ff-run-ediff-merge-file)
    (define-key map (kbd "M-p")           'helm-find-files-history)
    (define-key map (kbd "C-c h")         'helm-ff-file-name-history)
    (define-key map (kbd "M-i")           'helm-ff-properties-persistent)
    (define-key map (kbd "C-}")           'helm-narrow-window)
    (define-key map (kbd "C-{")           'helm-enlarge-window)
    (define-key map (kbd "C-<backspace>") 'helm-ff-run-toggle-auto-update)
    (define-key map (kbd "C-c <DEL>")     'helm-ff-run-toggle-auto-update)
    (define-key map (kbd "C-c C-a")       'helm-ff-run-mail-attach-files)
    (define-key map (kbd "C-c p")         'helm-ff-run-print-file)
    (define-key map (kbd "C-c /")         'helm-ff-run-find-sh-command)
    ;; Next 2 have no effect if candidate is not an image file.
    (define-key map (kbd "M-l")           'helm-ff-rotate-left-persistent)
    (define-key map (kbd "M-r")           'helm-ff-rotate-right-persistent)
    (define-key map (kbd "C-l")           'helm-find-files-up-one-level)
    (define-key map (kbd "C-_")           'helm-ff-undo)
    (define-key map (kbd "C-r")           'helm-find-files-down-last-level)
    (define-key map (kbd "C-c r")         'helm-ff-run-find-file-as-root)
    (define-key map (kbd "C-x C-v")       'helm-ff-run-find-alternate-file)
    (define-key map (kbd "C-c @")         'helm-ff-run-insert-org-link)
    (define-key map (kbd "S-<f1>")        'helm-ff-sort-alpha)
    (define-key map (kbd "S-<f2>")        'helm-ff-sort-by-newest)
    (define-key map (kbd "S-<f3>")        'helm-ff-sort-by-size)
    (helm-define-key-with-subkeys map (kbd "DEL") ?\d 'helm-ff-delete-char-backward
                                  '((C-backspace . helm-ff-run-toggle-auto-update)
                                    ([C-c DEL] . helm-ff-run-toggle-auto-update))
                                  nil 'helm-ff-delete-char-backward--exit-fn)
    (when (fboundp 'tab-bar-mode)
      (define-key map (kbd "C-c C-t")       'helm-ff-find-file-other-tab))
    map)
  "Keymap for `helm-find-files'.")

(defvar helm-read-file-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map helm-map)
    (define-key map (kbd "<C-return>")    'helm-cr-empty-string)
    (define-key map (kbd "M-RET")         'helm-cr-empty-string)
    (define-key map (kbd "C-]")           'helm-ff-run-toggle-basename)
    (define-key map (kbd "C-.")           'helm-find-files-up-one-level)
    (define-key map (kbd "C-l")           'helm-find-files-up-one-level)
    (define-key map (kbd "C-_")           'helm-ff-undo)
    (define-key map (kbd "C-r")           'helm-find-files-down-last-level)
    (define-key map (kbd "C-c h")         'helm-ff-file-name-history)
    (define-key map (kbd "C-<backspace>") 'helm-ff-run-toggle-auto-update)
    (define-key map (kbd "C-c <DEL>")     'helm-ff-run-toggle-auto-update)
    (define-key map (kbd "RET")           'helm-ff-RET)
    (helm-define-key-with-subkeys map (kbd "DEL") ?\d 'helm-ff-delete-char-backward
                                  '((C-backspace . helm-ff-run-toggle-auto-update)
                                    ([C-c DEL] . helm-ff-run-toggle-auto-update))
                                  nil 'helm-ff-delete-char-backward--exit-fn)
    map)
  "Keymap for `helm-read-file-name'.")

(defcustom helm-ff-lynx-style-map t
  "Use arrow keys to navigate with `helm-find-files'.
Note that if you define this variable with `setq' your change
will have no effect, use customize instead."
  :group 'helm-files
  :type 'boolean
  :set (lambda (var val)
         (set var val)
         (if val
             (progn
               (define-key helm-find-files-map (kbd "<right>")  'helm-execute-persistent-action)
               (define-key helm-find-files-map (kbd "<left>")   'helm-find-files-up-one-level)
               (define-key helm-read-file-map (kbd "<right>")  'helm-execute-persistent-action)
               (define-key helm-read-file-map (kbd "<left>")   'helm-find-files-up-one-level))
           (define-key helm-find-files-map (kbd "<right>") nil)
           (define-key helm-find-files-map (kbd "<left>")  nil)
           (define-key helm-read-file-map (kbd "<right>") nil)
           (define-key helm-read-file-map (kbd "<left>")  nil))))

(defcustom helm-ff-DEL-up-one-level-maybe nil
  "Use DEL to maybe go up one level when non nil.

Going up one level works only when pattern is a directory endings
with \"/\", otherwise this command deletes char backward.

When nil always delete char backward."
  :group 'helm-files
  :type 'boolean)

;; Internal.
(defvar helm-find-files-doc-header " (\\<helm-find-files-map>\\[helm-find-files-up-one-level]: Go up one level)"
  "*The doc that is inserted in the Name header of a find-files or dired source.")
(defvar helm-ff-auto-update-flag nil
  "Internal, flag to turn on/off auto-update in `helm-find-files'.
Don't set it directly, use instead `helm-ff-auto-update-initial-value'.")
(defvar helm-ff-last-expanded nil
  "Store last expanded directory or file.")
(defvar helm-ff-default-directory nil)
(defvar helm-ff-history nil)
(defvar helm-ff-cand-to-mark nil)
(defvar helm-ff-url-regexp
  "\\`\\(news\\(post\\)?:\\|nntp:\\|mailto:\\|file:\\|\\(ftp\\|https?\\|telnet\\|gopher\\|www\\|wais\\):/?/?\\).*"
  "Same as `ffap-url-regexp' but match earlier possible url.")
;; helm-tramp-file-name-regexp is based on old version of
;; tramp-file-name-regexp i.e. "\\`/\\([^[/:]+\\|[^/]+]\\):" but it
;; seems it is wrong and a simpler regexp is enough, let's try it and
;; watch out!
(defvar helm-tramp-file-name-regexp "\\`/\\([^/:|]+\\):")
(defvar helm-marked-buffer-name "*helm marked*")
(defvar helm-ff--auto-update-state nil)
(defvar helm-ff--deleting-char-backward nil)
(defvar helm-multi-files--toggle-locate nil)
(defvar helm-ff--move-to-first-real-candidate t)
(defvar helm-find-files--toggle-bookmark nil)
(defvar helm-ff--tramp-methods nil)
(defvar helm-ff--directory-files-hash (make-hash-table :test 'equal))
(defvar helm-ff-history-buffer-name "*helm-find-files history*")

;;; Helm-find-files
;;
;;
(defcustom helm-find-files-actions
  (helm-make-actions
   "Find File" 'helm-find-file-or-marked
   "Find file in Dired" 'helm-point-file-in-dired
   "View file" 'view-file
   "Query replace fnames on marked `M-@'" 'helm-ff-query-replace-fnames-on-marked
   "Marked files in dired `C-x C-q, C-u wdired'" 'helm-marked-files-in-dired
   "Query replace contents on marked `M-%'" 'helm-ff-query-replace
   "Query replace regexp contents on marked `C-M-%'" 'helm-ff-query-replace-regexp
   "Attach file(s) to mail buffer `C-c C-a'" 'helm-ff-mail-attach-files
   "Serial rename files" 'helm-ff-serial-rename
   "Serial rename by symlinking files" 'helm-ff-serial-rename-by-symlink
   "Serial rename by copying files" 'helm-ff-serial-rename-by-copying
   "Open file with default tool" 'helm-open-file-with-default-tool
   "Find file in hex dump" 'hexl-find-file
   "Browse project `C-x C-d'" 'helm-ff-browse-project
   "Complete at point `C-c i'" 'helm-insert-file-name-completion-at-point
   "Insert as org link `C-c @'" 'helm-files-insert-as-org-link
   "Find shell command `C-c /'" 'helm-ff-find-sh-command
   "Add marked files to file-cache" 'helm-ff-cache-add-file
   "Open file externally `C-c C-x, C-u to choose'" 'helm-open-file-externally
   "Grep File(s) `C-s, C-u Recurse'" 'helm-find-files-grep
   "Grep current directory with AG `M-g a, C-u select type'" 'helm-find-files-ag
   "Git grep `M-g g, C-u from root'" 'helm-ff-git-grep
   "Zgrep File(s) `M-g z, C-u Recurse'" 'helm-ff-zgrep
   "Pdf Grep File(s)" 'helm-ff-pdfgrep
   "Gid `M-g i'" 'helm-ff-gid
   "Switch to Eshell `M-e'" 'helm-ff-switch-to-shell
   "Etags `M-., C-u reload tag file'" 'helm-ff-etags-select
   "Eshell command on file(s) `M-!, C-u take all marked as arguments.'"
   'helm-find-files-eshell-command-on-file
   "Find file as root `C-c r'" 'helm-find-file-as-root
   "Find alternate file `C-x C-v'" 'find-alternate-file
   "Ediff File `C-c ='" 'helm-find-files-ediff-files
   "Ediff Merge File `M-='" 'helm-find-files-ediff-merge-files
   (lambda () (format "Delete File(s)%s `M-D' (C-u reverse trash)"
                      (if (eq helm-ff-delete-files-function
                              'helm-delete-marked-files-async)
                          " async" "")))
   'helm-ff-delete-files
   "Touch File(s) `M-T'" 'helm-ff-touch-files
   "Copy file(s) `M-C, C-u to follow'" 'helm-find-files-copy
   (lambda ()
     (and (executable-find "rsync")
          "Rsync file(s) `M-V'"))
   'helm-find-files-rsync
   "Rename file(s) `M-R, C-u to follow'" 'helm-find-files-rename
   "Backup files" 'helm-find-files-backup
   "Symlink files(s) `M-S, C-u to follow'" 'helm-find-files-symlink
   "Relsymlink file(s) `M-Y, C-u to follow'" 'helm-find-files-relsymlink
   "Hardlink file(s) `M-H, C-u to follow'" 'helm-find-files-hardlink
   "Find file other window `C-c o'" 'helm-find-files-other-window
   "Find file other frame `C-c C-o'" 'find-file-other-frame
   (lambda () (and (fboundp 'tab-bar-mode)
                   "Find file other tab `C-c C-t'"))
   'find-file-other-tab
   "Print File `C-c p, C-u to refresh'" 'helm-ff-print
   "Locate `C-x C-f, C-u to specify locate db'" 'helm-ff-locate)
  "Actions for `helm-find-files'."
  :group 'helm-files
  :type '(alist :key-type string :value-type function))

(defvar helm-source-find-files nil
  "The main source to browse files.
Should not be used among other sources.")

(defclass helm-source-ffiles (helm-source-sync)
  ((header-name
    :initform (lambda (name)
                (concat name (substitute-command-keys
                              helm-find-files-doc-header))))
   (init
    :initform (lambda ()
                (setq helm-ff-auto-update-flag
                      helm-ff-auto-update-initial-value)
                (setq helm-ff--auto-update-state
                      helm-ff-auto-update-flag)
                (helm-set-local-variable 'bookmark-make-record-function
                                         #'helm-ff-make-bookmark-record)
                (require 'helm-external)))
   (candidates :initform 'helm-find-files-get-candidates)
   (filtered-candidate-transformer
    :initform '((lambda (candidates _source)
                  (when helm-ff-use-dir-locals
                    (helm-ff--hack-dir-locals))
                  (cl-loop for f in candidates
                           for ff = (helm-ff-filter-candidate-one-by-one f)
                           when ff collect ff))
                helm-ff-sort-candidates))
   (persistent-action-if :initform 'helm-find-files-persistent-action-if)
   (persistent-help :initform "Hit1 Expand Candidate, Hit2 or (C-u) Find file")
   (help-message :initform 'helm-ff-help-message)
   (mode-line :initform (list "File(s)" helm-mode-line-string))
   (volatile :initform t)
   (cleanup :initform 'helm-find-files-cleanup)
   (migemo :initform t)
   (nohighlight :initform t)
   (keymap :initform helm-find-files-map)
   (candidate-number-limit :initform 'helm-ff-candidate-number-limit)
   (action-transformer
    :initform 'helm-find-files-action-transformer)
   (action :initform 'helm-find-files-actions)
   (before-init-hook :initform 'helm-find-files-before-init-hook)
   (after-init-hook :initform 'helm-find-files-after-init-hook)
   (group :initform 'helm-files)))

;; Bookmark handlers.
;;
(defun helm-ff-make-bookmark-record ()
  "The `bookmark-make-record-function' for `helm-find-files'."
  (with-helm-buffer
    `((filename . ,helm-ff-default-directory)
      (presel . ,(helm-get-selection))
      (handler . helm-ff-bookmark-jump))))

(defun helm-ff-bookmark-jump (bookmark)
  "bookmark handler for `helm-find-files'."
  (let ((fname (bookmark-prop-get bookmark 'filename))
        (presel (bookmark-prop-get bookmark 'presel)))
    ;; Force tramp connection with `file-directory-p' before lauching
    ;; hff otherwise the directory name is inserted on top before
    ;; tramp starts and display candidates.  FNAME is here always a
    ;; directory.
    (when (file-directory-p fname)
      (helm-find-files-1 fname (if helm-ff-transformer-show-only-basename
                                   (concat "^" (regexp-quote (helm-basename presel)))
                                 (regexp-quote presel))))))

(defun helm-ff-bookmark-set ()
  "Record `helm-find-files' session in bookmarks."
  (interactive)
  (with-helm-alive-p
    (with-helm-buffer
      (bookmark-set
       (concat helm-find-files-bookmark-prefix
               (abbreviate-file-name helm-ff-default-directory))))
    (message "Helm find files session bookmarked! ")))
(put 'helm-ff-bookmark-set 'helm-only t)

(defcustom helm-dwim-target nil
  "Default target directory for file actions.

Define the directory where you want to start navigating for the
target directory when copying, renaming, etc..  You can use the
`default-directory' of `next-window', the current
`default-directory' or have completion on all the directories
belonging to each window."
  :group 'helm-files
  :type '(radio :tag "Define default target directory for file actions."
          (const :tag "Directory belonging to next window" next-window)
          (const :tag "Completion on directories belonging to each window" completion)
          (const :tag "Use initial directory or `default-directory'" nil)))

(defun helm-dwim-target-directory ()
  "Try to return a suitable directory according to `helm-dwim-target'."
  (with-helm-current-buffer
    (let* ((wins (remove (get-buffer-window helm-marked-buffer-name)
                         (window-list)))
           (num-windows (length wins)))
      (expand-file-name
       (cond ((and (> num-windows 1)
                   (eq helm-dwim-target 'completion))
              (helm-comp-read "Browse target starting from: "
                              (append (list (or (car-safe helm-ff-history)
                                                default-directory)
                                            default-directory)
                                      (cl-loop for w in wins collect
                                               (with-selected-window w
                                                 default-directory)))))
             ((and (> num-windows 1)
                   (eq helm-dwim-target 'next-window))
              (with-selected-window (next-window)
                default-directory))
             ((or (= num-windows 1)
                  (null helm-dwim-target))
              ;; Using the car of *ff-history allow
              ;; staying in the directory visited instead of
              ;; current.
              (or (car-safe helm-ff-history) default-directory)))))))

(defun helm-ff--count-and-collect-dups (files)
  (cl-loop with dups = (make-hash-table :test 'equal)
           for f in files
           for file = (if (file-directory-p f)
                          (concat (helm-basename f) "/")
                          (helm-basename f))
           for count = (gethash file dups)
           if count do (puthash file (1+ count) dups)
           else do (puthash file 1 dups)
           finally return (cl-loop for k being the hash-keys in dups
                                   using (hash-value v)
                                   if (> v 1)
                                   collect (format "%s(%s)" k v)
                                   else
                                   collect k)))

(defun helm-find-files-do-action (action)
  "Generic function for creating actions from `helm-source-find-files'.
ACTION can be `rsync' or any action supported by `helm-dired-action'."
  (require 'dired-async)
  (when (eq action 'rsync)
    (cl-assert (executable-find "rsync") nil "No command named rsync"))
  (let* ((ifiles (mapcar 'expand-file-name ; Allow modify '/foo/.' -> '/foo'
                         (helm-marked-candidates :with-wildcard t)))
         (cand   (helm-get-selection)) ; Target
         (prefarg helm-current-prefix-arg)
         (prompt (format "%s %s file(s) %s: "
                         (if (and (and (fboundp 'dired-async-mode)
                                       dired-async-mode)
                                  (not (eq action 'rsync))
                                  (null prefarg))
                             (concat "Async " (symbol-name action))
                           (capitalize (symbol-name action)))
                         (length ifiles)
                         (if (memq action '(symlink relsymlink hardlink))
                             "from" "to")))
         helm-ff--move-to-first-real-candidate
         helm-display-source-at-screen-top ; prevent setting window-start.
         helm-ff-auto-update-initial-value
         ;; It is not possible to rename a file to a boring name when
         ;; helm-ff-skip-boring-files is enabled
         helm-ff-skip-boring-files
         ;; If HFF is using a frame use a frame as well.
         (helm-actions-inherit-frame-settings t)
         helm-use-frame-when-more-than-two-windows
         (dest   (with-helm-display-marked-candidates
                   helm-marked-buffer-name
                   (helm-ff--count-and-collect-dups ifiles)
                   (with-helm-current-buffer
                     (helm-read-file-name
                      prompt
                      :preselect (unless (cdr ifiles)
                                   (concat
                                    "^"
                                    (regexp-quote
                                     (if helm-ff-transformer-show-only-basename
                                         (helm-basename cand) cand))))
                      :initial-input (helm-dwim-target-directory)
                      :history (helm-find-files-history nil :comp-read nil)))))
         (dest-dir-p (file-directory-p dest))
         (dest-dir   (helm-basedir dest)))
    (unless (or dest-dir-p (file-directory-p dest-dir))
      (when (y-or-n-p (format "Create directory `%s'? " dest-dir))
        (make-directory dest-dir t)))
    (if (eq action 'rsync)
        (helm-rsync-copy-files ifiles dest)
      (helm-dired-action
       dest :files ifiles :action action :follow prefarg))))

;; Rsync
;;
(defcustom helm-rsync-switches '("-a" "-z" "-h" "--info=all2")
  "Rsync options to use with HFF Rsync action.
Note: Using \"--info=all2\" allows having the name of the file
currently transfered in an help-echo in mode-line, if you use
\"--info=progress2\" you will not have this information.  Using
\"--protect-args\" option may clash as we are already quoting
names."
  :type '(repeat string)
  :group 'helm-files)

(defcustom helm-rsync-percent-sign "％"
  "Percentage unicode sign to use in Rsync reporter."
  :type 'string
  :group 'helm-files)

(defcustom helm-rsync-no-mode-line-update nil
  "When non nil don't update mode-line when rsync is running.
This is useful if you display the progress bar somewhere else,
e.g. with minibuffer-line in minibuffer, in this case updating
mode-line may create flickering in other frame's mode-line."
  :type 'boolean
  :group 'helm-files)

(defvar helm-rsync-process-buffer "*helm-rsync*")
(defvar helm-rsync-progress-str-alist nil)

(defface helm-ff-rsync-progress
  '((t (:inherit font-lock-warning-face)))
  "Face used for rsync mode-line indicator."
  :group 'helm-files-faces)

(defun helm-rsync-remote2rsync (file)
  (if (file-remote-p file)
      (let ((localname (directory-file-name
                        (expand-file-name (file-remote-p file 'localname))))
            (user      (file-remote-p file 'user))
            (host      (file-remote-p file 'host)))
        (if user
            (format "%s@%s:%s" user host (helm-rsync-quote-argument localname))
          (format "%s:%s" host (helm-rsync-quote-argument localname))))
    (directory-file-name
     (expand-file-name file))))

(defun helm-rsync-quote-argument (fname)
  ;; Seems rsync already quote things like accentued chars and failed
  ;; when passing such chars already quoted, so quote only spaces and
  ;; only for remote path as specified in its documentation. IOW
  ;; shell-quote-argument is not working with Rsync.
  (mapconcat 'identity (split-string fname) "\\ "))

(defvar helm-rsync--last-progress-bar-alist nil
  "Used to store last valid rsync progress bar.")
(defun helm-rsync-format-mode-line-str (proc)
  (helm-aif (and (process-live-p proc)
                 (assoc-default proc helm-rsync-progress-str-alist))
      (progn
        ;; When rsync progress bar stop for some reason (e.g. rsync
        ;; takes time to finalize writing file to disk), no output is
        ;; coming from filter process, as a result the progress bar
        ;; disapear for a while giving no information to user while
        ;; the rsync process continues, so keep printing the last valid
        ;; progress bar (stored in `helm-rsync--last-progress-bar-alist')
        ;; instead of sending empty string.
        (unless (equal it "")
          (push (cons proc it) helm-rsync--last-progress-bar-alist))
        (format " [%s]" (propertize
                         (assoc-default proc helm-rsync--last-progress-bar-alist)
                         'face 'helm-ff-rsync-progress)))))

(defun helm-rsync-mode-line (proc)
  "Add Rsync progress to the mode line."
  (or global-mode-string (setq global-mode-string '("")))
  (unless (member `(:eval (helm-rsync-format-mode-line-str ,proc))
		  global-mode-string)
    (setq global-mode-string
	  (append global-mode-string
		  `((:eval (helm-rsync-format-mode-line-str ,proc)))))))

(defun helm-rsync-restore-mode-line (proc)
  "Restore the mode line when Rsync finishes."
  (setq global-mode-string
	(remove `(:eval (helm-rsync-format-mode-line-str ,proc))
                global-mode-string))
  (setq helm-rsync--last-progress-bar-alist nil)
  (force-mode-line-update))

(defun helm-rsync-copy-files (files dest)
  (setq files (cl-loop for f in files
                       collect (helm-rsync-remote2rsync f))
        dest (helm-rsync-remote2rsync dest))
  (let* ((buf (generate-new-buffer-name helm-rsync-process-buffer))
         (proc (apply #'start-process
                      "rsync" buf "rsync"
                      (append helm-rsync-switches
                              (append files (list dest))))))
    (helm-rsync-mode-line proc)
    (set-process-sentinel proc `(lambda (process event)
                                  (cond ((string= event "finished\n")
                                         (message "%s copied %s files"
                                                  (capitalize (process-name process))
                                                  ,(length files)))
                                        (t (error "Process %s %s with code %s"
                                                  (process-name process)
                                                  (process-status process)
                                                  (process-exit-status process))))
                                  (setq helm-rsync-progress-str-alist
                                        (delete (assoc process helm-rsync-progress-str-alist)
                                                helm-rsync-progress-str-alist))
                                  (helm-rsync-restore-mode-line process)
                                  (force-mode-line-update)))
    (set-process-filter proc #'helm-rsync-process-filter)))

(defun helm-rsync-process-filter (proc output)
  (let ((inhibit-read-only t)
        fname progbar)
    (with-current-buffer (process-buffer proc)
      (when (string-match comint-password-prompt-regexp output)
        ;; FIXME: Fully not tested and
        ;; use an agent or auth-source
        ;; or whatever to get password if
        ;; available.
        (process-send-string
         proc (concat (read-passwd (match-string 0 output)) "\n")))
      ;; Extract the progress bar.
      (with-temp-buffer
        (insert output)
        (when (re-search-backward "[[:cntrl:]]" nil t)
          (setq progbar (buffer-substring-no-properties
                         (match-end 0) (point-max)))))
      ;; Insert the text, advancing the process marker.
      (save-excursion
        (goto-char (process-mark proc))
        (insert output)
        (set-marker (process-mark proc) (point)))
      (goto-char (process-mark proc))
      ;; Extract the file name currently
      ;; copied (Imply --info=all2 or all1).
      (save-excursion
        (when (re-search-backward "^[^[:cntrl:]]" nil t)
          (setq fname (helm-basename
                       (buffer-substring-no-properties
                        (point) (point-at-eol))))))
      ;; Now format the string for the mode-line.
      (let ((ml-str (mapconcat 'identity
                               (split-string
                                (replace-regexp-in-string
                                 "%" helm-rsync-percent-sign
                                 progbar)
                                " " t)
                               " ")))
        (setq ml-str (propertize ml-str 'help-echo
                                 (format "%s->%s" (process-name proc) fname)))
        ;; Now associate the formatted
        ;; progress-bar string with process.
        (helm-aif (assoc proc helm-rsync-progress-str-alist)
            (setcdr it ml-str)
          (setq helm-rsync-progress-str-alist
                (push (cons proc ml-str) helm-rsync-progress-str-alist))))
      ;; Finally update mode-line.
      (unless helm-rsync-no-mode-line-update
        (force-mode-line-update t)))))

(defun helm-find-files-rsync (_candidate)
  "Rsync files from `helm-find-files'."
  (helm-find-files-do-action 'rsync))

(defun helm-find-files-copy (_candidate)
  "Copy files from `helm-find-files'."
  (helm-find-files-do-action 'copy))

(defun helm-find-files-backup (_candidate)
  "Backup files from `helm-find-files'.
This reproduce the behavior of \"cp --backup=numbered from to\"."
  (cl-assert (and (fboundp 'dired-async-mode) dired-async-mode) nil
             "Backup only available when `dired-async-mode' is enabled")
  (helm-find-files-do-action 'backup))

(defun helm-find-files-rename (_candidate)
  "Rename files from `helm-find-files'."
  (helm-find-files-do-action 'rename))

(defun helm-find-files-symlink (_candidate)
  "Symlink files from `helm-find-files'."
  (helm-find-files-do-action 'symlink))

(defun helm-find-files-relsymlink (_candidate)
  "Relsymlink files from `helm-find-files'."
  (helm-find-files-do-action 'relsymlink))

(defun helm-find-files-hardlink (_candidate)
  "Hardlink files from `helm-find-files'."
  (helm-find-files-do-action 'hardlink))

(defun helm-find-files-other-window (_candidate)
  "Keep current-buffer and open files in separate windows.
When a prefix arg is detected files are opened in a vertical
windows layout."
  (let* ((files (helm-marked-candidates))
         (buffers (mapcar 'find-file-noselect files)))
    (helm-window-show-buffers buffers t)))

(defun helm-find-files-byte-compile (_candidate)
  "Byte compile elisp files from `helm-find-files'."
  (let ((files    (helm-marked-candidates :with-wildcard t))
        (parg     helm-current-prefix-arg))
    (cl-loop for fname in files
          do (byte-compile-file fname parg))))

(defun helm-find-files-load-files (_candidate)
  "Load elisp files from `helm-find-files'."
  (let ((files    (helm-marked-candidates :with-wildcard t)))
    (cl-loop for fname in files
          do (load fname))))

(defun helm-find-files-ediff-files-1 (candidate &optional merge)
  "Generic function to ediff/merge files in `helm-find-files'."
  (let* ((helm-dwim-target 'next-window)
         (bname  (helm-basename candidate))
         (marked (helm-marked-candidates :with-wildcard t))
         (prompt (if merge "Ediff Merge `%s' With File: "
                   "Ediff `%s' With File: "))
         (fun    (if merge 'ediff-merge-files 'ediff-files))
         (input  (helm-dwim-target-directory))
         (presel (if helm-ff-transformer-show-only-basename
                     (helm-basename candidate)
                   (expand-file-name
                    (helm-basename candidate)
                    input))))
    (if (= (length marked) 2)
        (funcall fun (car marked) (cadr marked))
      (funcall fun candidate (helm-read-file-name
                              (format prompt bname)
                              :initial-input input
                              :preselect presel)))))

(defun helm-find-files-ediff-files (candidate)
  (helm-find-files-ediff-files-1 candidate))

(defun helm-find-files-ediff-merge-files (candidate)
  (helm-find-files-ediff-files-1 candidate 'merge))

(defun helm-find-files-grep (_candidate)
  "Default action to grep files from `helm-find-files'."
  (helm-do-grep-1 (helm-marked-candidates :with-wildcard t)
                  helm-current-prefix-arg))

(defun helm-ff-git-grep (_candidate)
  "Default action to git-grep `helm-ff-default-directory'."
  (helm-grep-git-1 helm-ff-default-directory helm-current-prefix-arg))

(defun helm-find-files-ag (_candidate)
  (helm-grep-ag helm-ff-default-directory
                helm-current-prefix-arg))

(defun helm-ff-zgrep (_candidate)
  "Default action to zgrep files from `helm-find-files'."
  (helm-ff-zgrep-1 (helm-marked-candidates :with-wildcard t) helm-current-prefix-arg))

(defun helm-ff-pdfgrep (_candidate)
  "Default action to pdfgrep files from `helm-find-files'."
  (let* ((recurse nil)
         (cands (cl-loop for file in (helm-marked-candidates :with-wildcard t)
                         for dir = (file-directory-p file)
                         when dir do (setq recurse t)
                         when (or dir
                                  (string= (file-name-extension file) "pdf")
                                  (string= (file-name-extension file) "PDF"))
                         collect file)))
    (when cands
      (helm-do-pdfgrep-1 cands recurse))))

(defun helm-ff-etags-select (candidate)
  "Default action to jump to etags from `helm-find-files'."
  (when (get-buffer helm-action-buffer)
    (kill-buffer helm-action-buffer))
  (let* ((source-name (assoc-default 'name (helm-get-current-source)))
         (default-directory (if (string= source-name "Find Files")
                                helm-ff-default-directory
                              (file-name-directory candidate))))
    (helm-etags-select helm-current-prefix-arg)))

(defvar eshell-command-aliases-list nil)
(defvar helm-eshell-command-on-file-input-history nil)
(cl-defun helm-find-files-eshell-command-on-file-1 (&optional map)
  "Run `eshell-command' on CANDIDATE or marked candidates.
This is done possibly with an Eshell alias.  If no alias found,
you can type in an Eshell command.

Only aliases accepting a file as argument at the end of command
line are collected, i.e. aliases ending with \"$1\" or \"$*\".

Basename of CANDIDATE can be a wild-card.
E.g. you can do \"eshell-command command *.el\"
Where \"*.el\" is the CANDIDATE.

It is possible to do eshell-command command <CANDIDATE> <some
more args> like this: \"command %s some more args\".

If MAP is given run `eshell-command' on all marked files at once,
Otherwise, run `eshell-command' on each marked files.
In other terms, with a prefix arg do on the three marked files
\"foo\" \"bar\" \"baz\":

\"eshell-command command foo bar baz\"

otherwise do

\"eshell-command command foo\"
\"eshell-command command bar\"
\"eshell-command command baz\"

Note:
You have to setup some aliases in Eshell with the `alias' command
or by editing yourself the file `eshell-aliases-file' to make
this working."
  (require 'em-alias) (eshell-read-aliases-list)
  (when (or eshell-command-aliases-list
            (y-or-n-p "No eshell aliases found, run eshell-command without alias anyway? "))
    (let* ((cand-list (helm-marked-candidates :with-wildcard t))
           (default-directory (or helm-ff-default-directory
                                  ;; If candidate is an url *-ff-default-directory is nil
                                  ;; so keep value of default-directory.
                                  default-directory))
           helm-display-source-at-screen-top
           (helm-actions-inherit-frame-settings t)
           helm-use-frame-when-more-than-two-windows
           (command (with-helm-display-marked-candidates
                      helm-marked-buffer-name
                      (helm-ff--count-and-collect-dups
                       (mapcar 'helm-basename cand-list))
                      (with-helm-current-buffer
                        (helm-comp-read
                         "Command: "
                         (cl-loop for (a c) in (eshell-read-aliases-list)
                                  ;; Positional arguments may be double
                                  ;; quoted (Issue #1881).
                                  when (string-match "[\"]?.*\\(\\$1\\|\\$\\*\\)[\"]?\\'" c)
                                  collect (propertize a 'help-echo c) into ls
                                  finally return (sort ls 'string<))
                         :buffer "*helm eshell on file*"
                         :name "Eshell command"
                         :mode-line
                         '("Eshell alias"
                           "C-h m: Help, \\[universal-argument]: Insert output at point")
                         :help-message 'helm-esh-help-message
                         :input-history
                         'helm-eshell-command-on-file-input-history))))
           (alias-value (car (assoc-default command eshell-command-aliases-list)))
           cmd-line)
      (if (or (equal helm-current-prefix-arg '(16))
              (equal map '(16)))
          ;; Two time C-u from `helm-comp-read' mean print to current-buffer.
          ;; i.e `eshell-command' will use this value.
          (setq current-prefix-arg '(16))
          ;; Else reset the value of `current-prefix-arg'
          ;; to avoid printing in current-buffer.
          (setq current-prefix-arg nil))
      (if (and (or
                ;; One prefix-arg have been passed before `helm-comp-read'.
                ;; If map have been set with C-u C-u (value == '(16))
                ;; ignore it.
                (and map (equal map '(4)))
                ;; One C-u from `helm-comp-read'.
                (equal helm-current-prefix-arg '(4))
                ;; An alias that finish with $*
                (and alias-value
                     ;; If command is an alias be sure it accept
                     ;; more than one arg i.e $*.
                     (string-match "\\$\\*$" alias-value)))
               (cdr cand-list))

          ;; Run eshell-command with ALL marked files as arguments.
          ;; This wont work on remote files, because tramp handlers depends
          ;; on `default-directory' (limitation).
          (let ((mapfiles (mapconcat 'shell-quote-argument cand-list " ")))
            (if (string-match "%s" command)
                (setq cmd-line (format command mapfiles)) ; See [1]
              (setq cmd-line (format "%s %s" command mapfiles)))
            (eshell-command cmd-line))

          ;; Run eshell-command on EACH marked files.
          ;; To work with tramp handler we have to call
          ;; COMMAND on basename of each file, using
          ;; its basedir as `default-directory'.
          (cl-loop for f in cand-list
                   for n from 1
                   for dir = (and (not (string-match helm--url-regexp f))
                                  (helm-basedir f))
                   ;; We can use basename here as the command will run
                   ;; under default-directory.
                   ;; This allow running e.g. "tar czvf test.tar.gz
                   ;; %s/*" without creating an archive expanding from /home.
                   for file = (shell-quote-argument (helm-basename f))
                   ;; \@ => placeholder for file without extension.
                   ;; \# => placeholder for incremental number.
                   for fcmd = (replace-regexp-in-string
                               "\\\\@" (regexp-quote (file-name-sans-extension file))
                               (replace-regexp-in-string
                                "\\\\#" (format "%03d" n) command))
                   for com = (if (string-match "%s" fcmd)
                                 ;; [1] This allow to enter other args AFTER filename
                                 ;; i.e <command %s some_more_args>
                                 (format fcmd file)
                               (format "%s %s" fcmd file))
                   do (let ((default-directory (or dir default-directory)))
                        (eshell-command com)))))))

(defun helm-find-files-eshell-command-on-file (_candidate)
  "Run `eshell-command' on CANDIDATE or marked candidates.
See `helm-find-files-eshell-command-on-file-1' for more info."
  (helm-find-files-eshell-command-on-file-1 helm-current-prefix-arg))

(defun helm-ff--shell-interactive-buffer-p (buffer &optional mode)
  (with-current-buffer buffer
    (when (eq major-mode (or mode 'eshell-mode))
      (let ((next-prompt-fn (cl-case major-mode
                              (shell-mode #'comint-next-prompt)
                              (eshell-mode #'eshell-next-prompt)
                              (term-mode #'term-next-prompt))))
        (save-excursion
          (goto-char (point-min))
          (funcall next-prompt-fn 1)
          (null (eql (point) (point-min))))))))

(defun helm-ff-switch-to-shell (_candidate)
  "Switch to Eshell or M-x shell and cd to `helm-ff-default-directory'.
Set your preferred shell mode in `helm-ff-preferred-shell-mode'.

With a numeric prefix arg switch to numbered shell buffer, if no
prefix arg provided and more than one shell buffer exists, provide
completions on those buffers. If only one shell buffer exists,
switch to this one, if no shell buffer exists or if the numeric
prefix arg shell buffer doesn't exists, create it and switch to it."
  ;; Reproduce the Emacs-25 behavior to be able to edit and send
  ;; command in term buffer.
  (let (term-char-mode-buffer-read-only      ; Emacs-25 behavior.
        term-char-mode-point-at-process-mark ; Emacs-25 behavior.
        (cd-eshell (lambda ()
                     (eshell/cd helm-ff-default-directory)
                     (eshell-reset)))
        (cd-shell
         (lambda ()
           (goto-char (point-max))
           (when (eq helm-ff-preferred-shell-mode 'shell-mode)
             (comint-delete-input))
           (insert (format "cd %s"
                           (shell-quote-argument
                            (or (file-remote-p
                                 helm-ff-default-directory 'localname)
                                helm-ff-default-directory))))
           (cl-case helm-ff-preferred-shell-mode
             (shell-mode (comint-send-input))
             (term-mode (progn (term-char-mode) (term-send-input))))))
        (bufs (cl-loop for b in (mapcar 'buffer-name (buffer-list))
                       when (helm-ff--shell-interactive-buffer-p
                             b helm-ff-preferred-shell-mode)
                       collect b)))
    ;; Jump to a shell buffer or open a new session.
    (helm-aif (and (not helm-current-prefix-arg)
                   (if (cdr bufs)
                       (helm-comp-read "Switch to shell buffer: " bufs
                                       :must-match t)
                     (car bufs)))
        (switch-to-buffer it)
      (cl-case helm-ff-preferred-shell-mode
        (eshell-mode
         (eshell helm-current-prefix-arg))
        (shell-mode
         (shell (helm-aif (and helm-current-prefix-arg
                               (prefix-numeric-value
                                helm-current-prefix-arg))
                    (format "*shell<%s>*" it))))
        (term-mode
         (progn
           (ansi-term (getenv "SHELL")
                      (helm-aif (and helm-current-prefix-arg
                                     (prefix-numeric-value
                                      helm-current-prefix-arg))
                          (format "*ansi-term<%s>*" it)))
           (term-line-mode)))))
    ;; Now cd into directory.
    (helm-aif (and (memq major-mode '(shell-mode term-mode))
                   (get-buffer-process (current-buffer)))
        (accept-process-output it 0.1))
    (unless (helm-ff-shell-alive-p major-mode)
      (funcall
       (if (eq major-mode 'eshell-mode) cd-eshell cd-shell)))))

(defun helm-ff-shell-alive-p (mode)
  "Returns non nil when a process is running inside `shell-mode' buffer."
  (cl-ecase mode
    (shell-mode
     (save-excursion
       (comint-goto-process-mark)
       (or (null comint-last-prompt)
           (not (eql (point)
                     (marker-position (cdr comint-last-prompt)))))))
    (eshell-mode
     (get-buffer-process (current-buffer)))
    (term-mode
     (save-excursion
       (goto-char (term-process-mark))
       (not (looking-back "\\$ " (- (point) 2)))))))

(defun helm-ff-touch-files (_candidate)
  "The touch files action for helm-find-files."
  (let* ((files (helm-marked-candidates))
         (split (cl-loop for f in files
                         for spt = (unless helm-current-prefix-arg
                                     (cons (helm-basedir f)
                                           (split-string f ", ?")))
                         if spt
                         append (cl-loop with dir = (car spt)
                                         for ff in (cdr spt)
                                         collect (expand-file-name ff dir))
                         else collect f))
         (timestamp (helm-comp-read
                     "Timestamp (default Now): "
                     (cl-loop for f in split
                              for time = (file-attributes f)
                              for date = (and time
                                              (format-time-string
                                               "%Y-%m-%d %H:%M:%S"
                                               (nth 5 time)))
                              when date
                              collect (cons (format "%s: %s"
                                                    (helm-basename f) date)
                                            date))
                     :default
                     (format-time-string "%Y-%m-%d %H:%M:%S"
                                         (current-time))))
         (failures
          (cl-loop with default-directory = helm-ff-default-directory
                   for f in split
                   for file = (or (file-remote-p f 'localname) f)
                   when (> (process-file
                            "touch" nil nil nil "-d" timestamp file)
                           0)
                   collect f)))
    (when failures
      (message "Failed to touch *%s files:\n%s"
               (length failures)
               (mapconcat (lambda (f) (format "- %s\n" f)) failures "")))))

(defun helm-ff-run-touch-files ()
  "Used to interactively run touch file action from keyboard."
  (interactive)
  (with-helm-alive-p
    (helm-exit-and-execute-action 'helm-ff-touch-files)))
(put 'helm-ff-run-touch-files 'helm-only t)

(defun helm-ff-sort-by-size ()
  (interactive)
  (unless (eq helm-ff-initial-sort-method 'size)
    (setq helm-ff-initial-sort-method 'size)
    (helm-update (helm-get-selection nil helm-ff-transformer-show-only-basename)))
  (message "Sorting by size"))
(put 'helm-ff-sort-by-size 'helm-only t)

(defun helm-ff-sort-by-newest ()
  (interactive)
  (unless (eq helm-ff-initial-sort-method 'newest)
    (setq helm-ff-initial-sort-method 'newest)
    (helm-update (helm-get-selection nil helm-ff-transformer-show-only-basename)))
  (message "Sorting by newest"))
(put 'helm-ff-sort-by-newest 'helm-only t)

(defun helm-ff-sort-alpha ()
  (interactive)
  (unless (eq helm-ff-initial-sort-method nil)
    (setq helm-ff-initial-sort-method nil)
    (helm-update (helm-get-selection nil helm-ff-transformer-show-only-basename)))
  (message "Sorting alphabetically"))
(put 'helm-ff-sort-alpha 'helm-only t)

(defun helm-ff-serial-rename-action (method)
  "Rename all marked files in `helm-ff-default-directory' with METHOD.
See `helm-ff-serial-rename-1'."
  (let* ((helm--reading-passwd-or-string t)
         (cands     (helm-marked-candidates :with-wildcard t))
         (def-name  (car cands))
         (name      (helm-read-string "NewName: "
                                      (replace-regexp-in-string
                                       "[0-9]+$" ""
                                       (helm-basename
                                        def-name
                                        (file-name-extension def-name)))))
         (start     (read-number "StartAtNumber: "))
         (extension (helm-read-string "Extension: "
                                      (file-name-extension (car cands))))
         (dir       (expand-file-name
                     (helm-read-file-name
                      "Serial Rename to directory: "
                      :initial-input
                      (expand-file-name helm-ff-default-directory)
                      :test 'file-directory-p
                      :must-match t)))
         done)
    (with-helm-display-marked-candidates
      helm-marked-buffer-name (helm-ff--count-and-collect-dups cands)
      (if (y-or-n-p
           (format "Rename %s file(s) to <%s> like this ?\n%s "
                   (length cands) dir (format "%s <-> %s%s.%s"
                                              (helm-basename (car cands))
                                              name start extension)))
          (progn
            (helm-ff-serial-rename-1
             dir cands name start extension :method method)
            (setq done t)
            (message nil))))
    (if done
        (with-helm-current-buffer (helm-find-files-1 dir))
      (message "Operation aborted"))))

(defun helm-ff-member-directory-p (file directory)
  (let ((dir-file (expand-file-name
                   (file-name-as-directory (file-name-directory file))))
        (cur-dir  (expand-file-name (file-name-as-directory directory))))
    (string= dir-file cur-dir)))

(cl-defun helm-ff-serial-rename-1
    (directory collection new-name start-at-num extension &key (method 'rename))
  "Rename files in COLLECTION to DIRECTORY with the prefix name NEW-NAME.
Rename start at number START-AT-NUM - ex: prefixname-01.jpg.
EXTENSION is the file extension to use.  In empty prompt, reuse
the original extension of file.
METHOD can be one of rename, copy or symlink.
Files will be renamed if they are files of current directory,
otherwise they will be treated with METHOD.
Default METHOD is rename."
  ;; Maybe remove directories selected by error in collection.
  (setq collection (cl-remove-if 'file-directory-p collection))
  (let* ((tmp-dir  (file-name-as-directory
                    (concat (file-name-as-directory directory)
                            (symbol-name (cl-gensym "tmp")))))
         (fn       (cl-case method
                     (copy    'copy-file)
                     (symlink 'make-symbolic-link)
                     (rename  'rename-file)
                     (t (error "Error: Unknown method %s" method)))))
    (make-directory tmp-dir)
    (unwind-protect
         (progn
           ;; Rename all files to tmp-dir with new-name.
           ;; If files are not from start directory, use method
           ;; to move files to tmp-dir.
           (cl-loop for i in collection
                 for count from start-at-num
                 for fnum = (if (< count 10) "0%s" "%s")
                 for nname = (concat tmp-dir new-name (format fnum count)
                                     (if (not (string= extension ""))
                                         (format ".%s" (replace-regexp-in-string
                                                        "[.]" "" extension))
                                       (file-name-extension i 'dot)))
                 do (if (helm-ff-member-directory-p i directory)
                        (rename-file i nname)
                      (funcall fn i nname)))
           ;; Now move all from tmp-dir to destination.
           (cl-loop with dirlist = (directory-files
                                    tmp-dir t directory-files-no-dot-files-regexp)
                 for f in dirlist do
                 (if (file-symlink-p f)
                     (make-symbolic-link (file-truename f)
                                         (concat (file-name-as-directory directory)
                                                 (helm-basename f)))
                   (rename-file f directory))))
      (delete-directory tmp-dir t))))

(defun helm-ff-serial-rename (_candidate)
  "Serial rename all marked files to `helm-ff-default-directory'.
Rename only file of current directory, and symlink files coming from
other directories.
See `helm-ff-serial-rename-1'."
  (helm-ff-serial-rename-action 'rename))

(defun helm-ff-serial-rename-by-symlink (_candidate)
  "Serial rename all marked files to `helm-ff-default-directory'.
Rename only file of current directory, and symlink files coming
from other directories.
See `helm-ff-serial-rename-1'."
  (helm-ff-serial-rename-action 'symlink))

(defun helm-ff-serial-rename-by-copying (_candidate)
  "Serial rename all marked files to `helm-ff-default-directory'.
Rename only file of current directory, and copy files coming from
other directories.
See `helm-ff-serial-rename-1'."
  (helm-ff-serial-rename-action 'copy))

(defvar helm-ff-query-replace-fnames-history-from nil)
(defvar helm-ff-query-replace-fnames-history-to nil)
(defun helm-ff-query-replace-on-filenames (candidates)
  "Query replace on filenames of CANDIDATES.
This doesn't replace inside the files, only modify filenames."
  (with-helm-display-marked-candidates
    helm-marked-buffer-name
    (mapcar 'helm-basename candidates)
    (let* ((regexp (read-string "Replace regexp on filename(s): "
                                nil 'helm-ff-query-replace-history-from
                                (helm-basename (car candidates))))
           (rep    (read-string (format "Replace regexp `%s' with: " regexp)
                                nil 'helm-ff-query-replace-history-to))
           subexp)
      (cl-loop with query = "y"
               with count = 0
               with target = nil
               for old in candidates
               for new = (concat (helm-basedir old)
                                 (helm--replace-regexp-in-buffer-string
                                  (save-match-data
                                    (cond ((string= regexp "%.")
                                           (setq subexp 1)
                                           (helm-ff--prepare-str-with-regexp
                                            (setq target (helm-basename old t))))
                                          ((string= regexp ".%")
                                           (setq subexp 1)
                                           (helm-ff--prepare-str-with-regexp
                                            (setq target (file-name-extension old))))
                                          ((string= regexp "%")
                                           (regexp-quote
                                            (setq target (helm-basename old))))
                                          ((string-match "%:\\([0-9]+\\):\\([0-9]+\\)" regexp)
                                           (setq subexp 1)
                                           (let ((beg (match-string 1 regexp))
                                                 (end (match-string 2 regexp))
                                                 (str (helm-basename old)))
                                             (setq target (substring str
                                                                     (string-to-number beg)
                                                                     (string-to-number end)))
                                             (helm-ff--prepare-str-with-regexp str beg end)))
                                          (t regexp)))
                                  (save-match-data
                                    (cond (;; Handle incremental
                                           ;; replacement with \# in
                                           ;; search and replace
                                           ;; feature in placeholder \@.
                                           (string-match
                                            "\\\\@/\\(.*\\)/\\(\\(?99:.*\\)\\\\#\\)/"
                                            rep)
                                           (replace-regexp-in-string
                                            (match-string 1 rep)
                                            (concat (match-string 99 rep)
                                                    (format "%03d" (1+ count)))
                                            target))
                                          ;; Incremental replacement
                                          ;; before or after \@.
                                          ((and (string-match-p "\\\\#" rep)
                                                (string-match "\\\\@" rep))
                                           (replace-regexp-in-string
                                            "\\\\#" (format "%03d" (1+ count))
                                            (replace-match target t t rep)))
                                          ;; Simple incremental replacement.
                                          ((string-match "\\\\#" rep)
                                           (replace-match
                                            (format "%03d" (1+ count)) t t rep))
                                          ;; Substring replacement in placeholder.
                                          ((string-match
                                            "\\\\@:\\([0-9]*\\):\\([0-9]*\\)" rep)
                                           (replace-match (substring
                                                           target
                                                           (string-to-number
                                                            (match-string 1 rep))
                                                           (pcase (match-string 2 rep)
                                                             ((pred (string= ""))
                                                              (length target))
                                                             (res (string-to-number res))))
                                                          t t rep))
                                          ;; Search and replace in
                                          ;; placeholder. Doesn't
                                          ;; handle incremental here.
                                          ((string-match "\\\\@/\\(.*\\)/\\(.*\\)/" rep)
                                           (replace-match (replace-regexp-in-string
                                                           (match-string 1 rep)
                                                           (match-string 2 rep)
                                                           target t)
                                                          t t rep))
                                          ;; Simple replacement by placeholder.
                                          ((string-match "\\\\@" rep)
                                           (replace-match target t t rep))
                                          ;; Replacement with
                                          ;; upcase, downcase or
                                          ;; capitalized text.
                                          ((string= rep "%u") #'upcase)
                                          ((string= rep "%d") #'downcase)
                                          ((string= rep "%c") #'capitalize)
                                          ;; Simple replacement with
                                          ;; whole replacement regexp.
                                          (t rep)))
                                  (helm-basename old) t nil subexp))
               ;; If `regexp' is not matched in `old'
               ;; `replace-regexp-in-string' will
               ;; return `old' unmodified.
               unless (string= old new)
               do (progn
                    (when (file-exists-p new)
                      (setq new (concat (file-name-sans-extension new)
                                        (format "(%s)" count)
                                        (file-name-extension new t))))
                    (unless (string= query "!")
                      (setq query (helm-read-answer (format
                                                     "Replace `%s' by `%s' [!,y,n,q]"
                                                     (helm-basename old)
                                                     (helm-basename new))
                                                    '("y" "n" "!" "q"))))
                    (when (string= query "q")
                      (cl-return (message "Operation aborted")))
                    (unless (string= query "n")
                      (rename-file old new)
                      (cl-incf count)))
               finally (message "%d Files renamed" count))))
  ;; This fix the emacs bug where "Emacs-Lisp:" is sent
  ;; in minibuffer (not the echo area).
  (sit-for 0.1)
  (with-current-buffer (window-buffer (minibuffer-window))
    (delete-minibuffer-contents)))

(defun helm-ff--prepare-str-with-regexp (str &optional rep1 rep2)
  ;; This is used in `helm-ff-query-replace-on-filenames' to prepare
  ;; STR when REGEXP is specified as substring e.g %:1:3 in this case
  ;; substring from 1 to 3 in STR will be enclosed with parenthesis to
  ;; match this substring as a subexp e.g %:1:3 on string "emacs" will
  ;; be replaced by "e\\(ma\\)cs" using subexp 1 like this:
  ;; (helm--replace-regexp-in-buffer-string "e\\(ma\\)cs" "fo" "emacs" nil t 1)
  ;; => "efocs"
  ;;      ^^
  ;; Where "1" and "3" will be strings extracted with match-string
  ;; from regexp and refered respectively in this function as REP1 and
  ;; REP2.
  (let* ((from   (or (and rep1 (string-to-number rep1)) 0))
         (to     (or (and rep2 (string-to-number rep2)) (length str)))
         (subexp (concat "\\(" (regexp-quote (substring str from to)) "\\)"))
         (before-str (unless (zerop from)
                       (regexp-quote (substring str 0 from))))
         (after-str (unless (= to (length str))
                      (regexp-quote (substring str to (length str))))))
    (concat before-str subexp after-str)))

;; The action.
(defun helm-ff-query-replace-fnames-on-marked (_candidate)
  (let ((marked (helm-marked-candidates :with-wildcard t)))
    (helm-ff-query-replace-on-filenames marked)))

;; The command for `helm-find-files-map'.
(defun helm-ff-run-query-replace-fnames-on-marked ()
  (interactive)
  (with-helm-alive-p
    (helm-exit-and-execute-action 'helm-ff-query-replace-fnames-on-marked)))
(put 'helm-ff-run-query-replace-fnames-on-marked 'helm-only t)

(defun helm-ff-query-replace (_candidate)
  (let ((bufs (cl-loop for f in (helm-marked-candidates :with-wildcard t)
                       collect (buffer-name (find-file-noselect f)))))
    (helm-buffer-query-replace-1 nil bufs)))

(defun helm-ff-query-replace-regexp (_candidate)
  (let ((bufs (cl-loop for f in (helm-marked-candidates :with-wildcard t)
                       collect (buffer-name (find-file-noselect f)))))
    (helm-buffer-query-replace-1 'regexp bufs)))

(defun helm-ff-run-query-replace ()
  (interactive)
  (with-helm-alive-p
    (helm-exit-and-execute-action 'helm-ff-query-replace)))
(put 'helm-ff-run-query-replace 'helm-only t)

(defun helm-ff-run-query-replace-regexp ()
  (interactive)
  (with-helm-alive-p
    (helm-exit-and-execute-action 'helm-ff-query-replace-regexp)))
(put 'helm-ff-run-query-replace-regexp 'helm-only t)

(defun helm-ff-toggle-auto-update (_candidate)
  (if helm-ff--deleting-char-backward
      (progn
        (message "[Auto expansion disabled]")
        (sit-for 1) (message nil)
        (setq helm-ff--auto-update-state nil))
    (setq helm-ff-auto-update-flag (not helm-ff-auto-update-flag))
    (setq helm-ff--auto-update-state helm-ff-auto-update-flag)
    (message "[Auto expansion %s]"
             (if helm-ff-auto-update-flag "enabled" "disabled"))))

(defun helm-ff-run-toggle-auto-update ()
  (interactive)
  (with-helm-alive-p
    (helm-attrset 'toggle-auto-update '(helm-ff-toggle-auto-update . never-split))
    (helm-execute-persistent-action 'toggle-auto-update)))
(put 'helm-ff-run-toggle-auto-update 'helm-only t)

(defun helm-ff-delete-char-backward ()
  "Go up one level or disable HFF auto update and delete char backward.

Going up one level works only when pattern is a directory endings
with \"/\", otherwise this command deletes char backward.

Going up one level can be disabled if necessary by deleting \"/\"
at end of pattern using \\<helm-map>\\[backward-char] and
\\[helm-delete-minibuffer-contents]."
  (interactive)
  (with-helm-alive-p
    (if (and helm-ff-DEL-up-one-level-maybe
             (string-match "/\\'" helm-pattern)
             (file-directory-p helm-pattern))
        (call-interactively 'helm-find-files-up-one-level)
      (setq helm-ff-auto-update-flag nil)
      (setq helm-ff--deleting-char-backward t)
      (call-interactively
       (lookup-key (current-global-map)
                   (read-kbd-macro "DEL")))
      (helm--update-header-line))))
(put 'helm-ff-delete-char-backward 'helm-only t)

(defun helm-ff-delete-char-backward--exit-fn ()
  (setq helm-ff-auto-update-flag helm-ff--auto-update-state)
  (setq helm-ff--deleting-char-backward nil))

(defvar helm-ff--RET-disabled nil)
(defun helm-ff-RET-1 (&optional must-match)
  "Used for RET action in `helm-find-files'.
See `helm-ff-RET' for details.
If MUST-MATCH is specified exit with
`helm-confirm-and-exit-minibuffer' which handle must-match mechanism."
  (let ((sel   (helm-get-selection))
        ;; Ensure `file-directory-p' works on remote files.
        non-essential)
    (cl-assert sel nil "Trying to exit with no candidates")
    (if (and (file-directory-p sel)
             ;; Allows exiting with default action when a prefix arg
             ;; is specified.
             (null current-prefix-arg)
             (null helm-ff--RET-disabled)
             (not (string= "." (helm-basename sel))))
        (helm-execute-persistent-action)
      (if must-match
          (helm-confirm-and-exit-minibuffer)
        (helm-maybe-exit-minibuffer)))))

(defun helm-ff-RET ()
  "Default action for RET in `helm-find-files'.

Behave differently depending on `helm-selection':

- candidate basename is \".\" => open it in dired.
- candidate is a directory    => expand it.
- candidate is a file         => open it."
  (interactive)
  (helm-ff-RET-1))
(put 'helm-ff-RET 'helm-only t)

(defun helm-ff-TAB-1 (&optional force-menu)
  "Used for TAB action in `helm-find-files'."
  (let ((sel (helm-get-selection)))
    (if (and (null force-menu)
             (file-directory-p sel)
             (not (string= "." (helm-basename sel))))
        (helm-execute-persistent-action)
      (helm-select-action))))

(defun helm-ff-TAB (arg)
  "Default action for TAB in `helm-find-files'.

Behave differently depending on `helm-selection':

- candidate basename is \".\" => open the action menu.
- candidate is a directory    => expand it.
- candidate is a file         => open action menu.

Called with a prefix arg open menu unconditionally."
  (interactive "P")
  (helm-ff-TAB-1 arg))
(put 'helm-ff-TAB 'helm-only t)

(defun helm-ff-RET-must-match ()
  "Same as `helm-ff-RET' but used in must-match map."
  (interactive)
  (helm-ff-RET-1 t))

(defun helm-ff-run-grep ()
  "Run Grep action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-exit-and-execute-action 'helm-find-files-grep)))
(put 'helm-ff-run-grep 'helm-only t)

(defun helm-ff-run-git-grep ()
  "Run git-grep action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-exit-and-execute-action 'helm-ff-git-grep)))
(put 'helm-ff-run-git-grep 'helm-only t)

(defun helm-ff-run-grep-ag ()
  (interactive)
  (with-helm-alive-p
    (helm-exit-and-execute-action 'helm-find-files-ag)))
(put 'helm-ff-run-grep-ag 'helm-only t)

(defun helm-ff-run-pdfgrep ()
  "Run Pdfgrep action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-exit-and-execute-action 'helm-ff-pdfgrep)))
(put 'helm-ff-run-pdfgrep 'helm-only t)

(defun helm-ff-run-zgrep ()
  "Run Grep action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-exit-and-execute-action 'helm-ff-zgrep)))
(put 'helm-ff-run-zgrep 'helm-only t)

(defun helm-ff-run-copy-file ()
  "Run Copy file action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-exit-and-execute-action 'helm-find-files-copy)))
(put 'helm-ff-run-copy-file 'helm-only t)

(defun helm-ff-run-rsync-file ()
  "Run Rsync file action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-exit-and-execute-action 'helm-find-files-rsync)))
(put 'helm-ff-run-rsync-file 'helm-only t)

(defun helm-ff-run-rename-file ()
  "Run Rename file action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-exit-and-execute-action 'helm-find-files-rename)))
(put 'helm-ff-run-rename-file 'helm-only t)

(defun helm-ff-run-byte-compile-file ()
  "Run Byte compile file action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-exit-and-execute-action 'helm-find-files-byte-compile)))
(put 'helm-ff-run-byte-compile-file 'helm-only t)

(defun helm-ff-run-load-file ()
  "Run Load file action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-exit-and-execute-action 'helm-find-files-load-files)))
(put 'helm-ff-run-load-file 'helm-only t)

(defun helm-ff-run-eshell-command-on-file ()
  "Run eshell command on file action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-exit-and-execute-action
     'helm-find-files-eshell-command-on-file)))
(put 'helm-ff-run-eshell-command-on-file 'helm-only t)

(defun helm-ff-run-ediff-file ()
  "Run Ediff file action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-exit-and-execute-action 'helm-find-files-ediff-files)))
(put 'helm-ff-run-ediff-file 'helm-only t)

(defun helm-ff-run-ediff-merge-file ()
  "Run Ediff merge file action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-exit-and-execute-action
     'helm-find-files-ediff-merge-files)))
(put 'helm-ff-run-ediff-merge-file 'helm-only t)

(defun helm-ff-run-symlink-file ()
  "Run Symlink file action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-exit-and-execute-action 'helm-find-files-symlink)))
(put 'helm-ff-run-symlink-file 'helm-only t)

(defun helm-ff-run-relsymlink-file ()
  "Run Symlink file action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-exit-and-execute-action 'helm-find-files-relsymlink)))
(put 'helm-ff-run-relsymlink-file 'helm-only t)

(defun helm-ff-run-hardlink-file ()
  "Run Hardlink file action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-exit-and-execute-action 'helm-find-files-hardlink)))
(put 'helm-ff-run-hardlink-file 'helm-only t)

(defun helm-ff-delete-files (candidate)
  "Delete files default action."
  (funcall helm-ff-delete-files-function candidate))

(defun helm-ff-run-delete-file ()
  "Run Delete file action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-exit-and-execute-action #'helm-ff-delete-files)))
(put 'helm-ff-run-delete-file 'helm-only t)

(defun helm-ff-run-complete-fn-at-point ()
  "Run complete file name action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-exit-and-execute-action
     'helm-insert-file-name-completion-at-point)))
(put 'helm-ff-run-complete-fn-at-point 'helm-only t)

(defun helm-ff-run-switch-to-shell ()
  "Run switch to eshell action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-exit-and-execute-action 'helm-ff-switch-to-shell)))
(put 'helm-ff-run-switch-to-shell 'helm-only t)

(defun helm-ff-run-switch-other-window ()
  "Run switch to other window action from `helm-source-find-files'.
When a prefix arg is provided, split is done vertically."
  (interactive)
  (with-helm-alive-p
    (helm-exit-and-execute-action 'helm-find-files-other-window)))
(put 'helm-ff-run-switch-other-window 'helm-only t)

(defun helm-ff-run-switch-other-frame ()
  "Run switch to other frame action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-exit-and-execute-action 'find-file-other-frame)))
(put 'helm-ff-run-switch-other-frame 'helm-only t)

(defun helm-ff-run-open-file-externally ()
  "Run open file externally command action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-exit-and-execute-action 'helm-open-file-externally)))
(put 'helm-ff-run-open-file-externally 'helm-only t)

(defun helm-ff-run-open-file-with-default-tool ()
  "Run open file externally command action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-exit-and-execute-action 'helm-open-file-with-default-tool)))
(put 'helm-ff-run-open-file-with-default-tool 'helm-only t)

(defun helm-ff-locate (candidate)
  "Locate action function for `helm-find-files'."
  (helm-locate-set-command)
  (let ((default (concat (helm-basename
                        (expand-file-name
                         candidate
                         helm-ff-default-directory))
                         (unless (or
                                  ;; "-b" is already added when fuzzy matching.
                                  helm-locate-fuzzy-match
                                  ;; The locate '-b' option doesn't exists
                                  ;; in everything (es).
                                  (and (eq system-type 'windows-nt)
                                       (string-match "^es" helm-locate-command)))
                           " -b"))))
    (helm-locate-1 helm-current-prefix-arg nil 'from-ff default)))

(defun helm-ff-run-locate ()
  "Run locate action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-exit-and-execute-action 'helm-ff-locate)))
(put 'helm-ff-run-locate 'helm-only t)

(defun helm-files-insert-as-org-link (candidate)
  (insert (format "[[%s][]]" candidate))
  (goto-char (- (point) 2)))

(defun helm-ff-run-insert-org-link ()
  (interactive)
  (with-helm-alive-p
    (helm-exit-and-execute-action 'helm-files-insert-as-org-link)))
(put 'helm-ff-run-insert-org-link 'helm-only t)

(defun helm-ff-run-find-file-as-root ()
  (interactive)
  (with-helm-alive-p
    (helm-exit-and-execute-action 'helm-find-file-as-root)))
(put 'helm-ff-run-find-file-as-root 'helm-only t)

(defun helm-ff-run-find-alternate-file ()
  (interactive)
  (with-helm-alive-p
    (helm-exit-and-execute-action 'find-alternate-file)))
(put 'helm-ff-run-find-alternate-file 'helm-only t)

(defun helm-ff-run-mail-attach-files ()
  "Run mail attach files command action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-exit-and-execute-action 'helm-ff-mail-attach-files)))
(put 'helm-ff-run-mail-attach-files 'helm-only t)

(defun helm-ff-run-etags ()
  "Run Etags command action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-exit-and-execute-action 'helm-ff-etags-select)))
(put 'helm-ff-run-etags 'helm-only t)

(defvar lpr-printer-switch)
(defun helm-ff-print (_candidate)
  "Print marked files.

You may to set in order variables `lpr-command',`lpr-switches'
and/or `printer-name', but with no settings Helm should detect
your printer(s) and print with the default `lpr' settings.

NOTE: DO NOT set the \"-P\" flag in `lpr-switches'.  If you really
have to modify this, do it in `lpr-printer-switch'.

Same as `dired-do-print' but for Helm."
  (require 'lpr)
  (when (or helm-current-prefix-arg
            (not helm-ff-printer-list))
    (setq helm-ff-printer-list
          (helm-ff-find-printers)))
  (let* ((file-list (helm-marked-candidates :with-wildcard t))
         (len (length file-list))
         (printer-name (if helm-ff-printer-list
                           (helm-comp-read
                            "Printer: " helm-ff-printer-list)
                         printer-name))
         (lpr-switches
	  (if (and (stringp printer-name)
		   (string< "" printer-name))
	      (cons (concat lpr-printer-switch printer-name)
		    lpr-switches)
              lpr-switches))
         (command (helm-read-string
                   (format "Print *%s File(s):\n%s with: "
                           len
                           (mapconcat
                            (lambda (f) (format "- %s\n" f))
                            file-list ""))
                   (when (and lpr-command lpr-switches)
                     (mapconcat 'identity
                                (cons lpr-command
                                      (if (stringp lpr-switches)
                                          (list lpr-switches)
                                          lpr-switches))
                                " "))))
         (file-args (mapconcat (lambda (x)
                                   (format "'%s'" x))
                               file-list " "))
         (cmd-line (concat command " " file-args)))
    (if command
        (start-process-shell-command "helm-print" nil cmd-line)
      (error "Error: Please verify your printer settings in Emacs."))))

(defun helm-ff-run-print-file ()
  "Run Print file action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-exit-and-execute-action 'helm-ff-print)))
(put 'helm-ff-run-print-file 'helm-only t)

(defun helm-ff-checksum (file)
  "Calculate the checksum of FILE.
The checksum is copied to `kill-ring'.
Checksum is calculated with the md5sum, sha1sum, sha224sum,
sha256sum, sha384sum and sha512sum when available, otherwise the
Emacs function `secure-hash' is used but it is slow and may crash
Emacs and even the whole system as it eats all memory."
  (cl-assert (file-regular-p file)
             nil "`%s' is not a regular file" file)
  (let* ((algo (intern (helm-comp-read
                        "Algorithm: "
                        '(md5 sha1 sha224 sha256 sha384 sha512))))
         (cmd  (concat (symbol-name algo) "sum"))
         (bn (helm-basename file))
         proc)
    (message "Calculating %s checksum for %s..." algo bn)
    (if (executable-find cmd)
        (progn
          (set-process-filter
           (setq proc (start-file-process cmd nil cmd "-b" file))
           (lambda (_process output)
             (when output (kill-new output))))
          (set-process-sentinel
           proc
           `(lambda (_process event)
              (when (string= event "finished\n")
                (message "Calculating %s checksum for `%s' done and copied to kill-ring"
                         ,(symbol-name algo) ,bn)))))
      (async-let ((sum (with-temp-buffer
                         (insert-file-contents-literally file)
                         (secure-hash algo (current-buffer)))))
        (kill-new sum)
        (message "Calculating %s checksum for `%s' done and copied to kill-ring"
                 algo bn)))))

(defun helm-ff-toggle-basename (_candidate)
  (with-helm-buffer
    (setq helm-ff-transformer-show-only-basename
          (not helm-ff-transformer-show-only-basename))
    (let* ((cand   (helm-get-selection nil t))
           (target (if helm-ff-transformer-show-only-basename
                       (helm-basename cand) cand)))
      (helm-force-update (concat (regexp-quote target) "$")))))

(defun helm-ff-run-toggle-basename ()
  (interactive)
  (with-helm-alive-p
    (unless (helm-empty-source-p)
      (helm-ff-toggle-basename nil))))
(put 'helm-ff-run-toggle-basename 'helm-only t)

(defun helm-reduce-file-name-1 (fname level)
  ;; This is the old version of helm-reduce-file-name, we still use it
  ;; with ftp fnames as expand-file-name is not working as expected
  ;; with ftp fnames (emacs bug).
  (cl-loop with result
           with iter = (helm-iter-reduce-fname (expand-file-name fname))
           repeat level do (setq result (helm-iter-next iter))
           finally return (or result (expand-file-name "/"))))

(defun helm-reduce-file-name-2 (fname level)
  ;; This version comes from issue #2004 (UNC paths) and should fix
  ;; it. It works with local files and remote files as well but not
  ;; with ftp, see helm-reduce-file-name-1.
  (while (> level 0)
    (unless (or (string= fname "/")
                (string= (file-remote-p fname 'localname) "/"))
      (setq fname (expand-file-name
                   (concat (expand-file-name fname) "/../"))))
    (setq level (1- level)))
  fname)

(defun helm-reduce-file-name (fname level)
  "Reduce FNAME by number LEVEL from end."
  (if (helm-aand (file-remote-p fname 'method)
                 (string= it "ftp"))
      (helm-reduce-file-name-1 fname level)
    (helm-reduce-file-name-2 fname level)))

(defun helm-iter-reduce-fname (fname)
  "Yield FNAME reduced by one level at each call."
  (let ((split (split-string fname "/" t)))
    (unless (or (null split)
                (string-match "\\`\\(~\\|[[:alpha:]]:\\)" (car split)))
      (setq split (cons "/" split)))
    (lambda ()
      (when (and split (cdr split))
        (cl-loop for i in (setq split (butlast split))
                 concat (if (string= i "/") i (concat i "/")))))))

(defvar helm-find-files--level-tree nil)
(defvar helm-find-files--level-tree-iterator nil)
(defun helm-find-files-up-one-level (arg)
  "Go up one level like unix command `cd ..'.
If prefix numeric arg is given go ARG level up."
  (interactive "p")
  (with-helm-alive-p
    (let ((src (helm-get-current-source)))
      (when (and (helm-file-completion-source-p src)
                 (not (helm-ff--invalid-tramp-name-p)))
        (with-helm-window
          (when (helm-follow-mode-p)
            (helm-follow-mode -1) (message nil)))
        ;; When going up one level we want to be at the line
        ;; corresponding to actual directory, so store this info
        ;; in `helm-ff-last-expanded'.
        (let ((cur-cand (helm-get-selection nil nil src))
              (new-pattern (helm-reduce-file-name helm-pattern arg)))
          ;; Ensure visibility on all candidates for preselection.
          (helm-attrset 'candidate-number-limit
                        (if helm-ff-up-one-level-preselect
                            (max (gethash new-pattern
                                          helm-ff--directory-files-hash
                                          helm-ff-candidate-number-limit)
                                 helm-ff-candidate-number-limit)
                          helm-ff-candidate-number-limit))
          (cond ((file-directory-p helm-pattern)
                 (setq helm-ff-last-expanded helm-ff-default-directory))
                ((file-exists-p helm-pattern)
                 (setq helm-ff-last-expanded helm-pattern))
                ((and cur-cand (file-exists-p cur-cand))
                 (setq helm-ff-last-expanded cur-cand)))
          (unless helm-find-files--level-tree
            (setq helm-find-files--level-tree
                  (cons helm-ff-default-directory
                        helm-find-files--level-tree)))
          (setq helm-find-files--level-tree-iterator nil)
          (push new-pattern helm-find-files--level-tree)
          (helm-set-pattern new-pattern helm-suspend-update-flag)
          (with-helm-after-update-hook (helm-ff-retrieve-last-expanded)))))))
(put 'helm-find-files-up-one-level 'helm-only t)

(defun helm-find-files-down-last-level ()
  "Retrieve previous paths reached by `C-l' in helm-find-files."
  (interactive)
  (with-helm-alive-p
    (when (and (helm-file-completion-source-p)
               (not (helm-ff--invalid-tramp-name-p)))
      (unless helm-find-files--level-tree-iterator
        (setq helm-find-files--level-tree-iterator
              (helm-iter-list (cdr helm-find-files--level-tree))))
      (setq helm-find-files--level-tree nil)
      (helm-aif (helm-iter-next helm-find-files--level-tree-iterator)
          (helm-set-pattern it)
        (setq helm-find-files--level-tree-iterator nil)))))
(put 'helm-find-files-down-last-level 'helm-only t)

(defun helm-find-files--reset-level-tree ()
  (setq helm-find-files--level-tree-iterator nil
        helm-find-files--level-tree nil))

(add-hook 'helm-cleanup-hook 'helm-find-files--reset-level-tree)
(add-hook 'post-self-insert-hook 'helm-find-files--reset-level-tree)
(add-hook 'helm-after-persistent-action-hook 'helm-find-files--reset-level-tree)

(defun helm-ff-retrieve-last-expanded ()
  "Move overlay to last visited directory `helm-ff-last-expanded'.
This happen after using `helm-find-files-up-one-level', or
hitting C-j on \"..\"."
  (when helm-ff-last-expanded
    (let ((presel (if helm-ff-transformer-show-only-basename
                      (helm-basename
                       (directory-file-name helm-ff-last-expanded))
                    (directory-file-name helm-ff-last-expanded))))
      (with-helm-window
        (when (re-search-forward (concat "^" (regexp-quote presel) "$") nil t)
          (forward-line 0)
          (helm-mark-current-line)))
      (setq helm-ff-last-expanded nil))))

(defun helm-ff-move-to-first-real-candidate ()
  "When candidate is an incomplete file name move to first real candidate."
  (let* ((src (helm-get-current-source))
         (name (assoc-default 'name src))
         ;; Ensure `helm-file-completion-source-p' returns nil on
         ;; `helm-read-file-name' history.
         minibuffer-completing-file-name)
    (helm-aif (and (helm-file-completion-source-p src)
                   (not (helm-empty-source-p))
                   ;; Prevent dired commands moving to first real
                   ;; (Issue #910).
                   (or (memq (intern-soft name)
                             helm-ff-goto-first-real-dired-exceptions)
                       (not (string-match "\\`[Dd]ired-" name)))
                   helm-ff--move-to-first-real-candidate
                   (helm-get-selection nil nil src))
        (unless (or (not (stringp it))
                    (and (string-match helm-tramp-file-name-regexp it)
                         (not (file-remote-p it nil t)))
                    (file-exists-p it))
          (helm-next-line)))))

(defun helm-ff-undo ()
  "Undo minibuffer in `helm-find-files'.
Ensure disabling `helm-ff-auto-update-flag' before undoing."
  (interactive)
  (let ((old--flag helm-ff-auto-update-flag))
    (setq helm-ff-auto-update-flag nil)
    (setq helm-ff--auto-update-state nil)
    (unwind-protect
        (progn
          (undo)
          (helm-check-minibuffer-input))
      (setq helm-ff-auto-update-flag old--flag)
      (setq helm-ff--auto-update-state helm-ff-auto-update-flag))))

;;; Auto-update - helm-find-files auto expansion of directories.
;;
;;
(defun helm-ff-update-when-only-one-matched ()
  "Expand to directory when sole completion.
When only one candidate is remaining and it is a directory,
expand to this directory.
This happen only when `helm-ff-auto-update-flag' is non-nil or
when `helm-pattern' is equal to \"~/\"."
  (let ((src (helm-get-current-source)))
    (when (and (helm-file-completion-source-p src)
               (not (get-buffer-window helm-action-buffer 'visible))
               (not (helm-ff--invalid-tramp-name-p))
               (not (string-match-p "\\`[.]\\{2\\}[^/]+"
                                    (helm-basename helm-pattern))))
      (with-helm-buffer
        (let* ((history-p   (string= (assoc-default 'name src)
                                     "Read File Name History"))
               (pat         (helm-ff-set-pattern helm-pattern))
               (completed-p (string= (file-name-as-directory
                                      (expand-file-name
                                       (substitute-in-file-name pat)))
                                     helm-ff-default-directory))
               (candnum (helm-get-candidate-number))
               (lt2-p   (and (<= candnum 2)
                             (>= (string-width (helm-basename helm-pattern)) 2)))
               (cur-cand (prog2
                             (unless (or completed-p
                                         (file-exists-p pat)
                                         history-p (null lt2-p))
                               ;; Only one non--existing candidate
                               ;; and one directory candidate, move to it,
                               ;; but not when renaming, copying etc...,
                               ;; so for this use
                               ;; `helm-ff-move-to-first-real-candidate'
                               ;; instead of `helm-next-line' (Issue #910).
                               (helm-ff-move-to-first-real-candidate))
                             (helm-get-selection nil nil src))))
          (when (and (or (and helm-ff-auto-update-flag
                              (null helm-ff--deleting-char-backward)
                              ;; Issue #295
                              ;; File predicates are returning t
                              ;; with paths like //home/foo.
                              ;; So check it is not the case by regexp
                              ;; to allow user to do C-a / to start e.g
                              ;; entering a tramp method e.g /sudo::.
                              (not (string-match "\\`//" helm-pattern))
                              (not (eq last-command 'helm-yank-text-at-point)))
                         ;; Fix issue #542.
                         (string= helm-pattern "~/")
                         ;; Only one remaining directory, expand it.
                         (and (= candnum 1)
                              helm-ff--auto-update-state
                              (file-accessible-directory-p pat)
                              (null helm-ff--deleting-char-backward)))
                     (or
                      ;; Only one candidate remaining
                      ;; and at least 2 char in basename.
                      lt2-p
                      ;; Already completed.
                      completed-p)
                     (not history-p) ; Don't try to auto complete in history.
                     (stringp cur-cand)
                     (file-accessible-directory-p cur-cand))
            (if (and (not (helm-dir-is-dot cur-cand)) ; [1]
                     ;; Maybe we are here because completed-p is true
                     ;; but check this again to be sure. (Windows fix)
                     (<= candnum 2))    ; [2]
                ;; If after going to next line the candidate
                ;; is not one of "." or ".." [1]
                ;; and only one candidate is remaining [2],
                ;; assume candidate is a new directory to expand, and do it.
                (helm-set-pattern (file-name-as-directory cur-cand))
                ;; The candidate is one of "." or ".."
                ;; that mean we have entered the last letter of the directory name
                ;; in prompt, so expansion is already done, just add the "/" at end
                ;; of name unless helm-pattern ends with "."
                ;; (i.e we are writing something starting with ".")
                (unless (string-match "\\`.*[.]\\{1\\}\\'" helm-pattern)
                  (helm-set-pattern
                   ;; Need to expand-file-name to avoid e.g /ssh:host:./ in prompt.
                   (expand-file-name (file-name-as-directory helm-pattern)))))
            ;; When typing pattern in minibuffer, helm
            ;; expand very fast to a directory matching pattern and
            ;; don't let undo the time to set a boundary, the result
            ;; is when e.g. going to root with "//" and undoing, undo
            ;; doesn't undo to previous input.  One fix for this is to
            ;; advice `undo-auto--boundary-ensure-timer' so that it is
            ;; possible to modify its delay (use a value of 1s for
            ;; helm), a second fix is to run directly here `undo-boundary'
            ;; inside a timer.
            (run-at-time helm-input-idle-delay nil #'undo-boundary)
            (helm-check-minibuffer-input)))))))

(defun helm-ff-auto-expand-to-home-or-root ()
  "Allow expanding to home/user directory or root or text yanked after pattern."
  (when (and (helm-file-completion-source-p)
             (with-current-buffer (window-buffer (minibuffer-window)) (eolp))
             (not (string-match helm-ff-url-regexp helm-pattern)))
    (cond ((and (not (file-remote-p helm-pattern))
                (null (file-exists-p helm-pattern))
                (string-match-p
                 "\\`\\([.]\\|\\s-\\)\\{2\\}[^/]+"
                 (helm-basename helm-pattern))
                (string-match-p "/\\'" helm-pattern))
           (helm-ff-recursive-dirs helm-pattern)
           (helm-ff--maybe-set-pattern-and-update))
          ((string-match
            "\\(?:\\`~/\\)\\|/?\\$.*/\\|/\\./\\|/\\.\\./\\|/~.*/\\|//\\|\\(/[[:alpha:]]:/\\|\\s\\+\\)"
            helm-pattern)
           (let* ((match (match-string 0 helm-pattern))
                  (input (cond ((string= match "/./")
                                (expand-file-name default-directory))
                               ((string= helm-pattern "/../") "/")
                               ((string-match-p "\\`/\\$" match)
                                (let ((sub (substitute-in-file-name match)))
                                  (if (file-directory-p sub)
                                      sub (replace-regexp-in-string "/\\'" "" sub))))
                               (t (helm-ff--expand-substitued-pattern helm-pattern)))))
             ;; `file-directory-p' returns t on "/home/me/." (issue #1844).
             (if (and (file-directory-p input)
                      (not (string-match-p "[^.]\\.\\'" input)))
                 (setq helm-ff-default-directory
                       (setq input (file-name-as-directory input)))
                 (setq helm-ff-default-directory (file-name-as-directory
                                                  (file-name-directory input))))
             (helm-ff--maybe-set-pattern-and-update input)))
          ((string-match "\\`/\\(-\\):.*" helm-pattern)
           (helm-ff--maybe-set-pattern-and-update
            (replace-match tramp-default-method t t helm-pattern 1))))))

(defun helm-ff--maybe-set-pattern-and-update (&optional str)
  (with-helm-window
    (when str (helm-set-pattern str))
    (helm-check-minibuffer-input)))

(defun helm-ff--expand-file-name-no-dot (name &optional directory)
  "Prevent expanding \"/home/user/.\" to \"/home/user\"."
  ;; Issue #1844 - If user enter "~/." to type an hidden filename
  ;; don't expand to /home/him e.g.
  ;; (expand-file-name "~/.") =>"/home/thierry"
  ;; (helm-ff--expand-substitued-pattern "~/.") =>"/home/thierry/."
  (concat (expand-file-name name directory)
          (and (string-match "[^.]\\.\\'" name) "/.")))

(defun helm-ff--expand-substitued-pattern (pattern)
  ;; [Windows] On UNC paths "/" expand to current machine,
  ;; so use the root of current Drive. (i.e "C:/")
  (let* ((directory (and (memq system-type '(windows-nt ms-dos))
                         (getenv "SystemDrive")))
         (subst (helm-substitute-in-filename pattern))
         ;; On Windows use a simple call to `expand-file-name' to
         ;; avoid Issue #2004.
         (expand-fn (if directory
                        #'expand-file-name
                      #'helm-ff--expand-file-name-no-dot)))
    ;; Fix issue #2223 with tilde in directory names e.g. "~/tmp/~test/".
    (funcall expand-fn (if (string-match-p "\\`~[^/]" subst)
                           pattern subst)
             ;; directory is nil on Nix.
             directory)))

(defun helm-substitute-in-filename (fname)
  "Substitute all parts of FNAME from start up to \"~/\" or \"/\".
On windows system substitute from start up to \"/[[:lower:]]:/\".
This function is needed for `helm-ff-auto-expand-to-home-or-root'
and should be used carefully elsewhere, or not at all, using
`substitute-in-file-name' instead."
  (cond ((and helm--url-regexp
              (string-match-p helm--url-regexp fname))
         fname)
        ((and (file-remote-p fname)
              helm-substitute-in-filename-stay-on-remote)
         (let ((sub (substitute-in-file-name fname)))
           (if (file-directory-p sub)
               sub (replace-regexp-in-string "/\\'" "" sub))))
        (t
         (with-temp-buffer
           (insert fname)
           (goto-char (point-min))
           (when (memq system-type '(windows-nt ms-dos))
             (skip-chars-forward "/")) ;; Avoid infloop in UNC paths Issue #424
           (if (re-search-forward "~.*/?\\|//\\|/[[:alpha:]]:/" nil t)
               (let ((match (match-string 0)))
                 (goto-char (if (or (string= match "//")
                                    (string-match-p "/[[:alpha:]]:/" match))
                                (1+ (match-beginning 0))
                                (match-beginning 0)))
                 (buffer-substring-no-properties (point) (point-at-eol)))
               fname)))))

(defun helm-point-file-in-dired (file)
  "Put point on filename FILE in dired buffer."
  (unless (and helm--url-regexp
               (string-match-p helm--url-regexp file))
    (let ((target (expand-file-name (helm-substitute-in-filename file))))
      (dired (file-name-directory target))
      (dired-goto-file target))))

(defun helm-marked-files-in-dired (_candidate)
  "Open a dired buffer with only marked files.

With a prefix arg toggle dired buffer to wdired mode."
  (advice-add 'wdired-finish-edit :override #'helm--advice-wdired-finish-edit)
  (advice-add 'wdired-get-filename :override #'helm--advice-wdired-get-filename)
  (let* ((marked (helm-marked-candidates :with-wildcard t))
         (current (car marked)))
    (unless (and helm--url-regexp
                 (string-match-p helm--url-regexp current))
      (let ((target (expand-file-name (helm-substitute-in-filename current))))
        (dired (cons helm-ff-default-directory marked))
        (dired-goto-file target)
        (when (or helm-current-prefix-arg current-prefix-arg)
          (call-interactively 'wdired-change-to-wdired-mode))))))

(defun helm-ff-run-marked-files-in-dired ()
  "Execute `helm-marked-files-in-dired' interactively."
  (interactive)
  (with-helm-alive-p
    (helm-exit-and-execute-action 'helm-marked-files-in-dired)))
(put 'helm-ff-run-marked-files-in-dired 'helm-only t)

(defun helm-ff--create-tramp-name (fname)
  "Build filename from `helm-pattern' like /su:: or /sudo::."
  ;; `tramp-make-tramp-file-name' takes 7 args on emacs-26 whereas it
  ;; takes only 5 args in emacs-24/25.
  (apply #'tramp-make-tramp-file-name
         ;; `tramp-dissect-file-name' returns a list in emacs-26
         ;; whereas in 24.5 it returns a vector, thus the car is a
         ;; symbol (`tramp-file-name') which is not needed as argument
         ;; for `tramp-make-tramp-file-name' so transform the cdr in
         ;; vector, and for 24.5 use directly the returned value.
         (cl-loop with v = (helm-ff--tramp-cons-or-vector
                            (tramp-dissect-file-name fname))
                  for i across v collect i)))

(defun helm-ff--tramp-cons-or-vector (vector-or-cons)
  "Return VECTOR-OR-CONS as a vector."
  (pcase vector-or-cons
    (`(,_l . ,ll) (vconcat ll))
    ((and vec (pred vectorp)) vec)))

(defun helm-ff--get-tramp-methods ()
  "Return a list of the car of `tramp-methods'."
  (or helm-ff--tramp-methods
      (setq helm-ff--tramp-methods (mapcar 'car tramp-methods))))

(defun helm-ff--previous-mh-tramp-method (str)
  (save-match-data
    (with-temp-buffer
      (insert str)
      (when (re-search-backward
             (concat "\\([|]\\)\\("
                     (mapconcat 'identity (helm-ff--get-tramp-methods) "\\|")
                     "\\):")
             nil t)
        (list
         (buffer-substring-no-properties (point-at-bol) (match-beginning 2))
         (buffer-substring-no-properties (match-beginning 2) (match-end 2)))))))

(defun helm-ff--get-host-from-tramp-invalid-fname (fname)
  "Extract hostname from an incomplete tramp file name.
Return nil on valid file name remote or not."
  ;; Check first if whole file is remote (file-remote-p is inefficient
  ;; in this case) otherwise we are matching e.g. /home/you/ssh:foo/
  ;; which is not a remote name.
  ;; FIXME this will not work with a directory or a file named like
  ;; "ssh:foo" and located at root (/) but it seems there is no real
  ;; solution apart disabling tramp-mode when a file/dir located at /
  ;; is matching helm-tramp-file-name-regexp; This would prevent usage
  ;; of tramp if one have such a directory at / (who would want to
  ;; have such a dir at / ???)  See emacs-bug#31489.
  (when (string-match-p helm-tramp-file-name-regexp fname)
    (let* ((bn    (helm-basename fname))
           (bd    (replace-regexp-in-string (regexp-quote bn) "" fname))
           (split (split-string bn ":" t))
           (meth  (car (member (car split)
                               (helm-ff--get-tramp-methods)))))
      (and meth (string= bd "/") (car (last split))))))

(cl-defun helm-ff--tramp-hostnames (&optional (pattern helm-pattern))
  "Get a list of hosts for tramp method found in `helm-pattern'.
Argument PATTERN default to `helm-pattern'.  It is here only for
debugging purpose."
  (when (string-match helm-tramp-file-name-regexp pattern)
    (let* ((mh-method   (helm-ff--previous-mh-tramp-method pattern))
           (method      (or (cadr mh-method) (match-string 1 pattern)))
           (current-mh-host (helm-aif (and mh-method
                                           (helm-ff--get-host-from-tramp-invalid-fname pattern))
                                (concat (car mh-method) method ":"
                                        (car (split-string it "|" t)))))
           (all-methods (helm-ff--get-tramp-methods))
           (comps (cl-loop for (f . h) in (tramp-get-completion-function method)
                           append (cl-loop for e in (funcall f (car h))
                                           for host = (and (consp e) (cadr e))
                                           ;; On emacs-27 host may be
                                           ;; ("root" t) in sudo method.
                                           when (and (stringp host)
                                                     (not (member host all-methods)))
                                           collect (concat (or (car mh-method) "/")
                                                           method ":" host)))))
      (helm-fast-remove-dups
       (delq nil (cons current-mh-host comps))
       :test 'equal))))

(defun helm-ff-before-action-hook-fn ()
  "Exit Helm when user try to execute action on an invalid tramp fname."
  (let* ((src (helm-get-current-source))
         (cand (helm-get-selection nil nil src)))
    (when (and (helm-file-completion-source-p src)
               (stringp cand)
               (helm-ff--invalid-tramp-name-p cand) ; Check candidate.
               (helm-ff--invalid-tramp-name-p)) ; check helm-pattern.
      (error "Error: Unknown file or directory `%s'" cand))))
(add-hook 'helm-before-action-hook 'helm-ff-before-action-hook-fn)

(cl-defun helm-ff--invalid-tramp-name-p (&optional (pattern helm-pattern))
  "Return non-nil when PATTERN is an invalid tramp filename."
  (string= (helm-ff-set-pattern pattern)
           "Invalid tramp file name"))

(defun helm-ff--tramp-postfixed-p (str)
  (let ((methods (helm-ff--get-tramp-methods))
        result)
    (save-match-data
      (with-temp-buffer
        (save-excursion (insert str))
        (helm-awhile (search-forward ":" nil t)
          (if (save-excursion
                (forward-char -1)
                (looking-back
                 (mapconcat (lambda (m) (format "[/|]%s" m)) methods "\\|")
                 (point-at-bol)))
              (setq result nil)
            (setq result it)))))
    result))

(defun helm-ff-set-pattern (pattern)
  "Handle tramp filenames in `helm-pattern'."
  (let* ((methods (helm-ff--get-tramp-methods))
         ;; Returns the position of last ":" entered.
         (postfixed (helm-ff--tramp-postfixed-p pattern))
         (reg "\\`/\\([^[/:]+\\|[^/]+]\\):.*:")
         cur-method tramp-name)
    (when (string-match "\\`/\\(-\\):" pattern)
      (setq pattern (replace-match tramp-default-method t t pattern 1)))
    ;; In some rare cases tramp can return a nil input,
    ;; so be sure pattern is a string for safety (Issue #476).
    (unless pattern (setq pattern ""))
    (cond ((string-match helm-ff-url-regexp pattern) pattern)
          ((string-match "\\`\\$" pattern)
           (substitute-in-file-name pattern))
          ((string= pattern "") "")
          ((string-match "\\`[.]\\{1,2\\}/\\'" pattern)
           (expand-file-name pattern))
          ;; Directories ending by a dot (issue #1940)
          ((string-match "[^/][.]/\\'" pattern)
           (expand-file-name pattern))
          ((string-match ".*\\(~?/?[.]\\{1\\}/\\)\\'" pattern)
           (expand-file-name default-directory))
          ((string-match ".*\\(~//\\|//\\)\\'" pattern)
           (expand-file-name "/"))      ; Expand to "/" or "c:/"
          ((string-match "\\`\\(~/\\|.*/~/\\)\\'" pattern)
           (expand-file-name "~/"))
          ((string-match "\\`~/" pattern)
           (expand-file-name pattern))
          ;; Match "/method:maybe_hostname:~"
          ((and (string-match (concat reg "~") pattern)
                postfixed
                (setq cur-method (match-string 1 pattern))
                (member cur-method methods))
           (setq tramp-name (expand-file-name
                             (helm-ff--create-tramp-name
                              (match-string 0 pattern))))
           (replace-match tramp-name nil t pattern))
          ;; Match "/method:maybe_hostname:"
          ((and (string-match reg pattern)
                postfixed
                (setq cur-method (match-string 1 pattern))
                (member cur-method methods))
           (setq tramp-name (helm-ff--create-tramp-name
                             (match-string 0 pattern)))
           (replace-match tramp-name nil t pattern))
          ;; Match "/hostname:"
          ((and (string-match helm-tramp-file-name-regexp pattern)
                postfixed
                (setq cur-method (match-string 1 pattern))
                (and cur-method (not (member cur-method methods))))
           (setq tramp-name (helm-ff--create-tramp-name
                             (match-string 0 pattern)))
           (replace-match tramp-name nil t pattern))
          ;; Match "/method:" in this case don't try to connect.
          ((and (null postfixed)
                (string-match helm-tramp-file-name-regexp pattern)
                (member (match-string 1 pattern) methods))
           "Invalid tramp file name")   ; Write in helm-buffer.
          ;; Return PATTERN unchanged.
          (t pattern))))

(defun helm-find-files-get-candidates (&optional require-match)
  "Create candidate list for `helm-source-find-files'."
  (let* ((path          (helm-ff-set-pattern helm-pattern))
         (dir-p         (file-accessible-directory-p path))
         basedir
         invalid-basedir
         non-essential
         (tramp-verbose helm-tramp-verbose)) ; No tramp message when 0.
    ;; Tramp check if path is valid without waiting a valid
    ;; connection and may send a file-error.
    (setq helm--ignore-errors (file-remote-p path))
    (set-text-properties 0 (length path) nil path)
    ;; Issue #118 allow creation of newdir+newfile.
    (unless (or
             ;; A tramp file name not completed.
             (string= path "Invalid tramp file name")
             ;; An empty pattern
             (string= path "")
             (and (string-match-p ":\\'" path)
                  (helm-ff--tramp-postfixed-p path))
             ;; Check if base directory of PATH is valid.
             (helm-aif (file-name-directory path)
                 ;; If PATH is a valid directory IT=PATH,
                 ;; else IT=basedir of PATH.
                 (file-directory-p it)))
      ;; BASEDIR is invalid, that's mean user is starting
      ;; to write a non--existing path in minibuffer
      ;; probably to create a 'new_dir' or a 'new_dir+new_file'.
      (setq invalid-basedir t))
    ;; Don't set now `helm-pattern' if `path' == "Invalid tramp file name"
    ;; like that the actual value (e.g /ssh:) is passed to
    ;; `helm-ff--tramp-hostnames'.
    (unless (or (string= path "Invalid tramp file name")
                invalid-basedir)      ; Leave  helm-pattern unchanged.
      (setq helm-ff-auto-update-flag  ; [1]
            ;; Unless auto update is disabled start auto updating only
            ;; at third char.
            (unless (or (null helm-ff--auto-update-state)
                        ;; But don't enable auto update when
                        ;; deleting backward.
                        helm-ff--deleting-char-backward
                        (and dir-p (not (string-match-p "/\\'" path))))
              (or (>= (length (helm-basename path)) 3) dir-p)))
      ;; At this point the tramp connection is triggered.
      (helm-log
       "Pattern=%S"
       (setq helm-pattern (helm-ff--transform-pattern-for-completion path)))
      ;; This have to be set after [1] to allow deleting char backward.
      (setq basedir (or (helm-aand
                         (if (and dir-p helm-ff-auto-update-flag)
                             ;; Add the final "/" to path
                             ;; when `helm-ff-auto-update-flag' is enabled.
                             (file-name-as-directory path)
                           (if (string= path "")
                               "/" (file-name-directory path)))
                         (expand-file-name it))
                        default-directory))
      (setq helm-ff-default-directory
            (if (string= helm-pattern "")
                (expand-file-name "/")  ; Expand to "/" or "c:/"
                ;; If path is an url *default-directory have to be nil.
                (unless (or (string-match helm-ff-url-regexp path)
                            (and helm--url-regexp
                                 (string-match helm--url-regexp path)))
                  basedir))))
    (when (and (string-match ":\\'" path)
               (file-remote-p basedir nil t))
      (setq helm-pattern basedir))
    (cond ((string= path "Invalid tramp file name")
           (or (helm-ff--tramp-hostnames) ; Hostnames completion.
               (prog2
                   ;; `helm-pattern' have not been modified yet.
                   ;; Set it here to the value of `path' that should be now
                   ;; "Invalid tramp file name" and set the candidates list
                   ;; to ("Invalid tramp file name") to make `helm-pattern'
                   ;; match single candidate "Invalid tramp file name".
                   (setq helm-pattern path)
                   ;; "Invalid tramp file name" is now printed
                   ;; in `helm-buffer'.
                   (list path))))
          ((or (and (file-regular-p path)
                    (eq last-repeatable-command 'helm-execute-persistent-action))
               ;; `ffap-url-regexp' don't match until url is complete.
               (string-match helm-ff-url-regexp path)
               invalid-basedir
               (and (not (file-exists-p path)) (string-match "/$" path))
               (and helm--url-regexp (string-match helm--url-regexp path)))
           (list path))
          ((string= path "") (helm-ff-directory-files "/"))
          ;; Check here if directory is accessible (not working on Windows).
          ((and (file-directory-p path) (not (file-readable-p path)))
           (list (format "file-error: Opening directory permission denied `%s'" path)))
          ;; A fast expansion of PATH is made only if `helm-ff-auto-update-flag'
          ;; is enabled.
          ((and dir-p helm-ff-auto-update-flag)
           (helm-ff-directory-files path))
          (t (append (unless (or require-match
                                 ;; Check here if path is an existing
                                 ;; file before adding it to
                                 ;; candidates, it was previously done
                                 ;; in the sort function but this
                                 ;; create a bug with remote files
                                 ;; when path is at the same time a
                                 ;; pattern matching a candidate and a
                                 ;; real candidate e.g. ack and
                                 ;; ack-grep in /usr/bin. This is due
                                 ;; presumably to a latency more
                                 ;; important with remote files which
                                 ;; lead to a confusion with the
                                 ;; pattern matching one candidate and
                                 ;; the real candidate which is same
                                 ;; as pattern.
                                 (file-exists-p path)
                                 ;; When `helm-ff-auto-update-flag' has been
                                 ;; disabled, whe don't want PATH to be added on top
                                 ;; if it is a directory.
                                 dir-p)
                       (list path))
                     (helm-ff-directory-files basedir))))))

(defun helm-list-directory (directory)
  "List directory DIRECTORY.

If DIRECTORY is remote use `helm-list-directory-function',
otherwise use `directory-files'."
  (let* ((remote (file-remote-p directory 'method))
         (helm-list-directory-function
          (if (and remote (not (string= remote "ftp")))
              helm-list-directory-function
            #'helm-list-dir-lisp))
         (remote-fn-p (eq helm-list-directory-function
                          'helm-list-dir-external))
         (sort-method (cl-case helm-ff-initial-sort-method
                        (newest (if (and remote remote-fn-p)
                                    "-t" #'file-newer-than-file-p))
                        (size (if (and remote remote-fn-p)
                                  "-S" #'helm-ff-file-larger-that-file-p))
                        (t nil))))
    (if remote
        (funcall helm-list-directory-function directory sort-method)
      (if sort-method
          (sort (directory-files directory t directory-files-no-dot-files-regexp)
                sort-method)
        (directory-files directory t directory-files-no-dot-files-regexp)))))

(defsubst helm-ff-file-larger-that-file-p (f1 f2)
  (let ((attr1 (file-attributes f1))
        (attr2 (file-attributes f2)))
    (> (nth 7 attr1) (nth 7 attr2))))

(defun helm-list-dir-lisp (directory &optional sort-method)
  "List DIRECTORY with `file-name-all-completions' as backend.

Add a `helm-ff-dir' property on each fname ending with \"/\"."
  ;; NOTE: `file-name-all-completions' and `directory-files' and most
  ;; tramp file handlers don't handle cntrl characters in fnames, so
  ;; the displayed files will be plain wrong in this case, even worst
  ;; the filenames will be splitted in two or more filenames.
  (cl-loop for f in (sort (file-name-all-completions "" directory)
                          (or sort-method 'string-lessp))
           unless (or (string= f "")
                      (member f '("./" "../"))
                      ;; Ignore the tramp names from /
                      ;; completion, e.g. ssh: scp: etc...
                      (char-equal (aref f (1- (length f))) ?:))
           if (and (helm--dir-name-p f)
                   (helm--dir-file-name f directory))
           collect (propertize it 'helm-ff-dir t)
           else collect (propertize (expand-file-name f directory)
                                    'helm-ff-file t)))

(defun helm-list-dir-external (dir &optional sort-method)
  "List directory DIR with external shell command as backend.

This function is fast enough to be used for remote files and save
the type of files at the same time in a property for using it
later in the transformer."
  (let ((default-directory (file-name-as-directory
                            (expand-file-name dir))))
    (with-temp-buffer
      (when (eq (process-file-shell-command
                 (format
                  ;; -A remove dot files, -F append [*=@|/>] at eof
                  ;; and -Q quote the real filename.  If not using -Q,
                  ;; there is no way to distinguish if foo* is a real
                  ;; file or if it is foo the executable file so with
                  ;; -Q we have "foo"* for the executable file foo and
                  ;; "foo*" for the real file foo. The downside is
                  ;; that we need an extra step to remove the quotes
                  ;; at the end which impact performances.
                  "ls -A -1 -F -b -Q %s | awk -v dir=%s '{print dir $0}'"
                  (or sort-method "")
                  (shell-quote-argument default-directory))
                 nil t nil)
                0)
        (goto-char (point-min))
        (save-excursion
          (while (re-search-forward "[*=@|/>]$" nil t)
            ;; A line looks like /home/you/"foo"@
            (helm-acase (match-string 0)
              ("*" (replace-match "")
                   (put-text-property
                    (point-at-bol) (point-at-eol) 'helm-ff-exe t))
              ("@" (replace-match "")
                   (put-text-property
                    (point-at-bol) (point-at-eol) 'helm-ff-sym t))
              ("/" (replace-match "")
                   (put-text-property
                    (point-at-bol) (point-at-eol) 'helm-ff-dir t))
              (("=" "|" ">") (replace-match "")))))
        (while (re-search-forward "[\"]" nil t)
          (replace-match ""))
        (add-text-properties (point-min) (point-max) '(helm-ff-file t))
        (split-string (buffer-string) "\n" t)))))

(defun helm-ff-directory-files (directory)
  "List contents of DIRECTORY.
Argument FULL mean absolute path.
It is same as `directory-files' but always returns the dotted
filename '.' and '..' even on root directories in Windows
systems."
  (setq directory (file-name-as-directory
                   (expand-file-name directory)))
  (let* (file-error
         (ls   (condition-case err
                   (helm-list-directory directory)
                 ;; Handle file-error from here for Windows
                 ;; because predicates like `file-readable-p' and friends
                 ;; seem broken on emacs for Windows systems (always returns t).
                 ;; This should never be called on GNU/Linux/Unix
                 ;; as the error is properly intercepted in
                 ;; `helm-find-files-get-candidates' by `file-readable-p'.
                 (file-error
                  (prog1
                      (list (format "%s:%s"
                                    (car err)
                                    (mapconcat 'identity (cdr err) " ")))
                    (setq file-error t)))))
        (dot  (concat directory "."))
        (dot2 (concat directory "..")))
    (puthash directory (+ (length ls) 2) helm-ff--directory-files-hash)
    (append (and (not file-error) (list dot dot2)) ls)))

(defun helm-ff-handle-backslash (fname)
  ;; Allow creation of filenames containing a backslash.
  (cl-loop with bad = '((92 . ""))
        for i across fname
        if (assq i bad) concat (cdr it)
        else concat (string i)))

(defun helm-ff-fuzzy-matching-p ()
  (and helm-ff-fuzzy-matching
       (not (memq helm-mm-matching-method '(multi1 multi3p)))))

(defun helm-ff--transform-pattern-for-completion (pattern)
  "Maybe return PATTERN with it's basename modified as a regexp.
This happens only when `helm-ff-fuzzy-matching' is enabled.
This provides a similar behavior as `ido-enable-flex-matching'.
See also `helm--mapconcat-pattern'.
If PATTERN is an url return it unmodified.
When PATTERN contains a space fallback to multi-match.
If basename contains one or more space fallback to multi-match.
If PATTERN is a valid directory name, return PATTERN unchanged."
  ;; handle bad filenames containing a backslash (no more needed in
  ;; emacs-26, also prevent regexp matching with e.g. "\|").
  ;; (setq pattern (helm-ff-handle-backslash pattern))
  (let ((bn      (helm-basename pattern))
        (bd      (or (helm-basedir pattern) ""))
        ;; Trigger tramp connection with file-directory-p.
        (dir-p   (file-directory-p pattern))
        (tramp-p (cl-loop for (m . f) in tramp-methods
                       thereis (string-match m pattern))))
    ;; Always regexp-quote base directory name to handle
    ;; crap dirnames such e.g bookmark+
    (cond
      ((or (and dir-p tramp-p (string-match ":\\'" pattern))
           (string= pattern "")
           (and dir-p (<= (length bn) 2))
           ;; Fix Issue #541 when BD have a subdir similar
           ;; to BN, don't switch to match plugin
           ;; which will match both.
           (and dir-p (string-match (regexp-quote bn) bd)))
       ;; Use full PATTERN on e.g "/ssh:host:".
       (regexp-quote pattern))
      ;; Prefixing BN with a space call multi-match completion.
      ;; This allow showing all files/dirs matching BN (Issue #518).
      ;; FIXME: some multi-match methods may not work here.
      (dir-p (concat (regexp-quote bd) " " (regexp-quote bn)))
      ((or (not (helm-ff-fuzzy-matching-p))
           (string-match "\\s-" bn))    ; Fall back to multi-match.
       (concat (regexp-quote bd) bn))
      ((or (string-match "[*][.]?.*" bn) ; Allow entering wildcard.
           (string-match "/$" pattern)     ; Allow mkdir.
           (string-match helm-ff-url-regexp pattern)
           (and (string= helm-ff-default-directory "/") tramp-p))
       ;; Don't treat wildcards ("*") as regexp char.
       ;; (e.g ./foo/*.el => ./foo/[*].el)
       (concat (regexp-quote bd)
               (replace-regexp-in-string "[*]" "[*]" bn)))
      (t (concat (regexp-quote bd)
                 (if (>= (length bn) 2) ; wait 2nd char before concating.
                     (helm--mapconcat-pattern bn)
                     (concat ".*" (regexp-quote bn))))))))

(defun helm-dir-is-dot (dir)
  (string-match "\\(?:/\\|\\`\\)\\.\\{1,2\\}\\'" dir))

(defun helm-ff-save-history ()
  "Store the last value of `helm-ff-default-directory' in `helm-ff-history'.
Note that only existing directories are saved here."
  (when (and helm-ff-default-directory
             (helm-file-completion-source-p)
             (file-directory-p helm-ff-default-directory))
    (set-text-properties 0 (length helm-ff-default-directory)
                         nil helm-ff-default-directory)
    (push helm-ff-default-directory helm-ff-history)))
(add-hook 'helm-cleanup-hook 'helm-ff-save-history)

(defun helm-files-save-file-name-history (&optional force)
  "Save marked files to `file-name-history'."
  (let* ((src (helm-get-current-source))
         (src-name (assoc-default 'name src)))
    (when (or force (helm-file-completion-source-p src)
              (member src-name helm-files-save-history-extra-sources))
      (let ((mkd (helm-marked-candidates :with-wildcard t))
            (history-delete-duplicates t))
        (cl-loop for sel in mkd
              when (and sel
                        (stringp sel)
                        (file-exists-p sel)
                        (not (file-directory-p sel)))
              do
              ;; we use `abbreviate-file-name' here because
              ;; other parts of Emacs seems to,
              ;; and we don't want to introduce duplicates.
              (add-to-history 'file-name-history
                              (abbreviate-file-name sel)))))))
(add-hook 'helm-exit-minibuffer-hook 'helm-files-save-file-name-history)

(defun helm-ff-valid-symlink-p (file)
  (helm-aif (condition-case-unless-debug nil
                ;; `file-truename' send error
                ;; on cyclic symlinks (Issue #692).
                (file-truename file)
              (error nil))
      (file-exists-p it)))

(defun helm-get-default-mode-for-file (filename)
  "Return the default mode to open FILENAME."
  (let ((mode (cl-loop for (r . m) in auto-mode-alist
                    thereis (and (string-match r filename) m))))
    (or (and (symbolp mode) mode) "Fundamental")))

(defun helm-ff-properties (candidate)
  "Show file properties of CANDIDATE in a tooltip or message."
  (require 'helm-external) ; For `helm-get-default-program-for-file'.
  (helm-aif (helm-file-attributes candidate)
      (let* ((dired-line         (helm-file-attributes
                                  candidate :dired t :human-size t))
             (type               (cl-getf it :type))
             (mode-type          (cl-getf it :mode-type))
             (owner              (cl-getf it :uid))
             (owner-right        (cl-getf it :user t))
             (group              (cl-getf it :gid))
             (group-right        (cl-getf it :group))
             (other-right        (cl-getf it :other))
             (trash              (and (helm-ff-trash-file-p candidate)
                                      (helm-ff--get-dest-file-from-trash
                                       (helm-ff-trash-list)
                                       (replace-regexp-in-string
                                        "\\.trashinfo\\'" "" candidate))))
             (size               (helm-file-human-size (cl-getf it :size)))
             (modif              (cl-getf it :modif-time))
             (access             (cl-getf it :access-time))
             (ext                (helm-get-default-program-for-file candidate))
             (tooltip-hide-delay (or helm-tooltip-hide-delay tooltip-hide-delay)))
        (if (and (display-graphic-p) tooltip-mode)
            (tooltip-show
             (concat
              (helm-basename candidate) "\n"
              dired-line "\n"
              (format "Mode: %s\n" (helm-get-default-mode-for-file candidate))
              (format "Ext prog: %s\n" (or (and ext (replace-regexp-in-string
                                                     " %s" "" ext))
                                           "Not defined"))
              (format "Type: %s: %s\n" type mode-type)
              (when (string= type "symlink")
                (format "True name: '%s'\n"
                        (cond ((string-match "^\.#" (helm-basename candidate))
                               "Autosave symlink")
                              ((helm-ff-valid-symlink-p candidate)
                               (file-truename candidate))
                              (t "Invalid Symlink"))))
              (format "Owner: %s: %s\n" owner owner-right)
              (format "Group: %s: %s\n" group group-right)
              (format "Others: %s\n" other-right)
              (format "Size: %s\n" size)
              (format "Modified: %s\n" modif)
              (format "Accessed: %s\n" access)
              (and (stringp trash)
                   (format "Trash: %s\n" 
                           (abbreviate-file-name trash)))))
          (message dired-line) (sit-for 5)))
    (message "Permission denied, file not readable")))

(defun helm-ff-properties-persistent ()
  "Show properties without quitting helm."
  (interactive)
  (with-helm-alive-p
    (helm-attrset 'properties-action '(helm-ff-properties . never-split))
    (helm-execute-persistent-action 'properties-action)))
(put 'helm-ff-properties-persistent 'helm-only t)

(defun helm-ff-persistent-delete ()
  "Delete current candidate without quitting."
  (interactive)
  (with-helm-alive-p
    (helm-attrset 'quick-delete '(helm-ff-quick-delete . never-split))
    (helm-execute-persistent-action 'quick-delete)))
(put 'helm-ff-persistent-delete 'helm-only t)

(defun helm-ff-dot-file-p (file)
  "Check if FILE is `.' or `..'."
  (member (helm-basename file) '("." "..")))

(defun helm-ff-kill-buffer-fname (candidate)
  (let* ((buf      (get-file-buffer candidate))
         (buf-name (buffer-name buf)))
    (cond ((and buf (eq buf (get-buffer helm-current-buffer)))
           (user-error
            "Can't kill `helm-current-buffer' without quitting session"))
          (buf (kill-buffer buf) (message "Buffer `%s' killed" buf-name))
          (t (message "No buffer to kill")))))

(defun helm-ff-kill-or-find-buffer-fname (candidate)
  "Find file CANDIDATE or kill its buffer if it is visible.
Never kill `helm-current-buffer'.
Never kill buffer modified.
This is called normally on third hit of \
\\<helm-map>\\[helm-execute-persistent-action]
in `helm-find-files-persistent-action-if'."
  (let* ((buf      (get-file-buffer candidate))
         (buf-name (buffer-name buf))
         (win (get-buffer-window buf))
         (helm--reading-passwd-or-string t))
    (cond ((and buf win (eq buf (get-buffer helm-current-buffer)))
           (user-error
            "Can't kill `helm-current-buffer' without quitting session"))
          ((and buf win (buffer-modified-p buf))
           (message "Can't kill modified buffer, please save it before"))
          ((and buf win)
           (kill-buffer buf)
           (if (and helm-persistent-action-display-window
                    (window-dedicated-p (next-window win 1)))
               (delete-window helm-persistent-action-display-window)
             (set-window-buffer win helm-current-buffer))
           (message "Buffer `%s' killed" buf-name))
          (t (find-file candidate)))))

(defun helm-ff-run-kill-buffer-persistent ()
  "Execute `helm-ff-kill-buffer-fname' without quitting."
  (interactive)
  (with-helm-alive-p
    (helm-attrset 'kill-buffer-fname 'helm-ff-kill-buffer-fname)
    (helm-execute-persistent-action 'kill-buffer-fname)))
(put 'helm-ff-run-kill-buffer-persistent 'helm-only t)

;; Preview with external tool
(defun helm-ff-persistent-open-file-externally (file)
  (require 'helm-external)
  (if (helm-get-default-program-for-file file)
      (helm-open-file-externally file)
    (message "Please configure an external program for `*%s' file in `helm-external-programs-associations'"
             (file-name-extension file t))))

(defun helm-ff-run-preview-file-externally ()
  (interactive)
  (with-helm-alive-p
    (helm-attrset 'open-file-externally '(helm-ff-persistent-open-file-externally . never-split))
    (helm-execute-persistent-action 'open-file-externally)))
(put 'helm-ff-run-preview-file-externally 'helm-only t)

(defun helm-ff-prefix-filename (fname &optional file-or-symlinkp new-file)
  "Return filename FNAME maybe prefixed with [?] or [@].
If FILE-OR-SYMLINKP is non-nil this means we assume FNAME is an
existing filename or valid symlink and there is no need to test
it.
NEW-FILE when non-nil means FNAME is a non existing file and
return FNAME prefixed with [?]."
  (let* ((prefix-new (propertize
                      " " 'display
                      (propertize "[?]" 'face 'helm-ff-prefix)))
         (prefix-url (propertize
                      " " 'display
                      (propertize "[@]" 'face 'helm-ff-prefix))))
    (cond (file-or-symlinkp fname)
          ((or (string-match helm-ff-url-regexp fname)
               (and helm--url-regexp (string-match helm--url-regexp fname)))
           (concat prefix-url " " fname))
          (new-file (concat prefix-new " " fname)))))

(defun helm-ff-score-candidate-for-pattern (real disp pattern)
  (if (or (member real '("." ".."))
          ;; Incomplete filenames are prefixed with two spaces, the
          ;; first one beeing propertized with a 'display prop
          ;; i.e. "[?] foo".
          (and (string-match-p "\\`\\s-\\{2\\}" disp)
               (string= real (substring-no-properties disp 2))))
      900000
      (helm-score-candidate-for-pattern real pattern)))

(defun helm-ff-sort-candidates-1 (candidates input)
  "Sort function for `helm-source-find-files'.
Return candidates prefixed with basename of INPUT first."
  (if (or (and (file-directory-p input)
               (string-match "/\\'" input))
          (string-match "\\`\\$" input)
          (null candidates))
      candidates
    (let* ((memo-src  (make-hash-table :test 'equal))
           (all (sort candidates
                      (lambda (s1 s2)
                        (let* ((score (lambda (disp real)
                                        (helm-ff-score-candidate-for-pattern
                                         disp real (helm-basename input))))
                               ;; Reals
                               (r1 (helm-basename (if (consp s1) (cdr s1) s1)))
                               (r2 (helm-basename (if (consp s2) (cdr s2) s2)))
                               ;; Displays
                               (d1 (helm-basename (if (consp s1) (car s1) s1)))
                               (d2 (helm-basename (if (consp s2) (car s2) s2)))
                               (sc1 (or (gethash r1 memo-src)
                                        (puthash r1 (funcall score r1 d1) memo-src)))
                               (sc2 (or (gethash r2 memo-src)
                                        (puthash r2 (funcall score r2 d2) memo-src))))
                          (cond ((= sc1 sc2)
                                 (< (string-width r1)
                                    (string-width r2)))
                                ((> sc1 sc2))))))))
      all)))

(defun helm-ff-sort-candidates (candidates _source)
  "Sort function for `helm-source-find-files'.
Return candidates prefixed with basename of `helm-input' first."
  (helm-ff-sort-candidates-1 candidates helm-input))

(defvar helm-ff--dir-locals nil)
(make-local-variable 'helm-ff--dir-locals)

(defun helm-ff--reset-dir-locals ()
  "Reset directory local variables to their default-value."
  (with-helm-buffer
    (cl-loop for (k . _v) in helm-ff--dir-locals
             when (default-boundp k)
             do (set (make-local-variable k) (default-value k)))))

(defun helm-ff--apply-dir-locals (locals)
  "Apply directory variables LOCALS (an alist) in helm-buffer."
  (with-helm-buffer
    ;; Reset all local vars that have been added by
    ;; `hack-local-variables-apply' to their default value.
    (helm-ff--reset-dir-locals)
    ;; Store possible dir local vars for further reset.
    (cl-loop for (k . v) in locals
             unless (assq k helm-ff--dir-locals)
             do (push (cons k v) helm-ff--dir-locals))
    ;; Now apply dir locals.
    (hack-local-variables-apply)))

(defun helm-ff--hack-dir-locals ()
  "Maybe apply directory local variables in helm-buffer."
  (with-helm-default-directory helm-ff-default-directory
    ;; Reset previous dir local vars in helm-buffer.
    (with-helm-buffer (setq dir-local-variables-alist nil))
    (hack-dir-local-variables)
    (helm-aif dir-local-variables-alist
        (helm-ff--apply-dir-locals it)
      (helm-ff--reset-dir-locals))))

(defun helm-ff-boring-file-p (file)
  "Returns non nil when FILE is matching boring regexps."
  ;; Prevent user doing silly thing like
  ;; adding the dotted files to boring regexps (#924).
  (and helm-ff-skip-boring-files
       (not (string-match "\\.$" file))
       (string-match  helm-ff--boring-regexp file)))

(defvar helm-ff--git-found-p nil)
(defun helm-ff-git-ignored-p (file)
  "Returns non nil when FILE is matched in \".gitignore\" file."
  (and helm-ff-skip-git-ignored-files
       (not (file-remote-p file))
       (or helm-ff--git-found-p
           (setq helm-ff--git-found-p (executable-find "git")))
       (zerop (call-process "git" nil nil nil "check-ignore" "-q" file))))

(defun helm-ff-filter-candidate-one-by-one (file)
  "`filter-one-by-one' Transformer function for `helm-source-find-files'."
  ;; Handle boring files
  (let ((basename (helm-basename file))
        dot)
    (unless (or (helm-ff-boring-file-p basename)
                (helm-ff-git-ignored-p file))

      ;; Handle tramp files with minimal highlighting.
      (if (and (or (string-match-p helm-tramp-file-name-regexp helm-pattern)
                   (helm-file-on-mounted-network-p helm-pattern)))
          (let* (hostp
                 (disp (if (and helm-ff-transformer-show-only-basename
                                (not (setq dot (helm-dir-is-dot file))))
                           (or (setq hostp
                                     (helm-ff--get-host-from-tramp-invalid-fname
                                      file))
                               basename)
                         file)))
            ;; Filename with cntrl chars e.g. foo^J
            ;; This will not work as long as most tramp file handlers doesn't
            ;; handle such case, e.g. file-name-all-completions,
            ;; directory-files, file-name-nondirectory etc...
            ;; Keep it though in case they fix this upstream...
            (setq disp (replace-regexp-in-string "[[:cntrl:]]" "?" disp))
            (cond (;; Dot directories . and ..
                   dot (propertize file 'face 'helm-ff-dotted-directory))
                  ;; Directories.
                  ((get-text-property 1 'helm-ff-dir file)
                   (cons (propertize disp 'face 'helm-ff-directory) file))
                  ;; Executable files.
                  ((get-text-property 1 'helm-ff-exe file)
                   (cons (propertize disp 'face 'helm-ff-executable) file))
                  ;; Symlinks.
                  ((get-text-property 1 'helm-ff-sym file)
                   (cons (propertize disp 'face 'helm-ff-symlink) file))
                  ;; Regular files.
                  ((get-text-property 1 'helm-ff-file file)
                   (cons (propertize disp 'face 'helm-ff-file) file))
                  ;; non existing files.
                  (t (cons (helm-ff-prefix-filename
                            (propertize disp 'face 'helm-ff-file)
                            hostp (unless hostp 'new-file))
                           file))))

        ;; Highlight local files showing everything, symlinks, exe,
        ;; dirs etc...
        (let* ((disp (if (and helm-ff-transformer-show-only-basename
                              (not (setq dot (helm-dir-is-dot file)))
                              (not (and helm--url-regexp
                                        (string-match helm--url-regexp file)))
                              (not (string-match helm-ff-url-regexp file)))
                         (or (helm-ff--get-host-from-tramp-invalid-fname file)
                             basename)
                       file))
               (attr (file-attributes file))
               (type (car attr))
               x-bit)
          ;; Filename cntrl chars e.g. foo^J
          (setq disp (replace-regexp-in-string "[[:cntrl:]]" "?" disp))
          (cond ((string-match "file-error" file) file)
                (;; A dead symlink.
                 (and (stringp type)
                      (not (helm-ff-valid-symlink-p file))
                      (not (string-match "^\\.#" basename)))
                 (cons (propertize disp 'face 'helm-ff-invalid-symlink)
                       file))
                ;; A dotted directory symlinked.
                ((and dot (stringp type))
                 (cons (propertize disp 'face 'helm-ff-dotted-symlink-directory)
                       file))
                ;; A dotted directory.
                ((helm-ff-dot-file-p file)
                 (cons (propertize disp 'face 'helm-ff-dotted-directory)
                       file))
                ;; A symlink.
                ((stringp type)
                 (cons (propertize disp 'display
                                   (concat (propertize disp 'face 'helm-ff-symlink)
                                           " -> "
                                           (propertize (abbreviate-file-name type)
                                                       'face 'helm-ff-truename)))
                       file))
                ;; A directory.
                ((eq t type)
                 (cons (propertize disp 'face 'helm-ff-directory)
                       file))
                ;; A character device file.
                ((and attr (string-match
                            "\\`[cp]" (setq x-bit (substring (nth 8 attr) 0 4))))
                 (cons (propertize disp 'face 'helm-ff-pipe)
                       file))
                ;; A socket file.
                ((and attr (string-match "\\`[s]" x-bit))
                 (cons (propertize disp 'face 'helm-ff-socket)
                       file))
                ;; An executable file.
                ((and attr
                      (string-match
                       "x\\'" x-bit))
                 (cons (propertize disp 'face 'helm-ff-executable)
                       file))
                ;; An executable file with suid
                ((and attr (string-match "s\\'" x-bit))
                 (cons (propertize disp 'face 'helm-ff-suid)
                       file))
                ;; A file.
                ((and attr (null type))
                 (cons (propertize disp 'face 'helm-ff-file)
                       file))
                ;; A non--existing file.
                (t (cons (helm-ff-prefix-filename
                          (propertize disp 'face 'helm-ff-file) nil 'new-file)
                         file))))))))

(defun helm-find-files-action-transformer (actions candidate)
  "Action transformer for `helm-source-find-files'."
  (let ((str-at-point (with-helm-current-buffer
                        (buffer-substring-no-properties
                         (point-at-bol) (point-at-eol)))))
    (when (file-regular-p candidate)
      (setq actions (helm-append-at-nth
                     actions '(("Checksum File" . helm-ff-checksum)) 4)))
    (cond ((and (file-exists-p candidate)
                (string-match "Trash/files/?\\'" (helm-basedir candidate))
                (not (member (helm-basename candidate) '("." "..")))
                (executable-find "trash"))
           (helm-append-at-nth
            actions
            '(("Restore file(s) from trash" . helm-restore-file-from-trash)
              ("Delete file(s) from trash" . helm-ff-trash-rm))
            1))
          ((and helm--url-regexp
                (not (string-match-p helm--url-regexp str-at-point))
                (not (with-helm-current-buffer (eq major-mode 'dired-mode)))
                (string-match-p ":\\([0-9]+:?\\)" str-at-point))
           (append '(("Find file to line number" . helm-ff-goto-linum))
                   actions))
          ((string-match (image-file-name-regexp) candidate)
           (helm-append-at-nth
            actions
            '(("Rotate image right `M-r'" . helm-ff-rotate-image-right)
              ("Rotate image left `M-l'" . helm-ff-rotate-image-left))
            3))
          ((string-match "\\.el\\'" (helm-aif (helm-marked-candidates)
                                        (car it) candidate))
           (helm-append-at-nth
            actions
            '(("Byte compile lisp file(s) `M-B, C-u to load'"
               . helm-find-files-byte-compile)
              ("Load File(s) `M-L'" . helm-find-files-load-files))
            2))
          ((string-match (concat (regexp-opt load-suffixes) "\\'")
                         (helm-aif (helm-marked-candidates)
                             (car it) candidate))
           (helm-append-at-nth
            actions
            '(("Load File(s) `M-L'" . helm-find-files-load-files))
            2))
          ((and (string-match "\\.html?$" candidate)
                (file-exists-p candidate))
           (helm-append-at-nth
            actions '(("Browse url file" . browse-url-of-file)) 2))
          (t actions))))

(defun helm-ff-trash-action (fn names &rest args)
  "Execute a trash action FN on marked files.

Arg NAMES is a list of strings to pass to messages.
E.g. '(\"delete\" \"deleting\")

ARGS are other arguments to be passed to FN."
  (let ((mkd (helm-marked-candidates))
        errors)
    (with-helm-display-marked-candidates
        helm-marked-buffer-name
        (helm-ff--count-and-collect-dups (mapcar 'helm-basename mkd))
        (if (y-or-n-p (format "%s %s files from trash? "
                              (capitalize (car names))
                              (length mkd)))
            (progn
              (message "%s files from trash..." (capitalize (cadr names)))
              (cl-loop for f in mkd do
                       (condition-case err
                           (apply fn f args)
                         (error (push (format "%s" (cadr err)) errors)
                                nil)))
              (if errors
                  (display-warning 'helm
                                   (with-temp-buffer
                                     (insert (format-time-string "%Y-%m-%d %H:%M:%S\n"
                                                                 (current-time)))
                                     (insert (format
                                              "Failed to %s %s/%s files from trash\n"
                                              (car names) (length errors) (length mkd)))
                                     (insert (mapconcat 'identity errors "\n") "\n")
                                     (buffer-string))
                                   :error
                                   "*helm restore warnings*")
                (message "%s %s files from trash done"
                         (capitalize (cadr names)) (length mkd))))
          (message "Restoring files from trash aborted")))))

(defun helm-ff-trash-rm (_candidate)
  "Delete marked-files from a Trash directory.

The Trash directory should be a directory compliant with
<http://freedesktop.org/wiki/Specifications/trash-spec> and each
file should have its '*.trashinfo' correspondent file in
Trash/info directory."
  (helm-ff-trash-action 'helm-ff-trash-rm-1 '("delete" "deleting")))

(defun helm-ff-trash-rm-1 (file)
  (let ((info-file (concat (helm-reduce-file-name file 2)
                           "info/" (helm-basename file "trashinfo")
                           ".trashinfo")))
    (cl-assert (file-exists-p file)
               nil (format "No such file or directory `%s'"
                           file))
    (cl-assert (file-exists-p info-file)
               nil (format "No such file or directory `%s'"
                           info-file))
    (if (file-directory-p file)
        (delete-directory file t)
      (delete-file file))
    (delete-file info-file)))

(defun helm-restore-file-from-trash (_candidate)
  "Restore marked-files from a Trash directory.

The Trash directory should be a directory compliant with
<http://freedesktop.org/wiki/Specifications/trash-spec> and each
file should have its '*.trashinfo' correspondent file in
Trash/info directory."
  (let* ((default-directory (file-name-as-directory
                             helm-ff-default-directory))
         (trashed-files     (helm-ff-trash-list)))
    (helm-ff-trash-action 'helm-restore-file-from-trash-1
                          '("restore" "restoring")
                          trashed-files)))

(defun helm-restore-file-from-trash-1 (file trashed-files)
  "Restore FILE from a trash directory.
Arg TRASHED-FILES is an alist of (fname_in_trash . dest) obtained
with `helm-ff-trash-list'."
  ;; Emacs trash duplicate files with a unique name + .trashinfo in
  ;; the filename which is wrong, only files in info directory should
  ;; end with .trashinfo, so fix the filename before looking for dest name.
  (let* ((fname (replace-regexp-in-string "\\.trashinfo\\'" "" file)) 
         (info-file (concat (helm-reduce-file-name fname 2)
                            "info/"
                            (helm-basename fname)
                            ".trashinfo"))
         (dest-file (helm-ff--get-dest-file-from-trash
                     trashed-files fname)))
    (cl-assert (not (file-exists-p dest-file)) nil
               (format "File `%s' already exists" dest-file))
    (cl-assert dest-file nil "No such file in trash")
    (message "Restoring %s to %s..." (helm-basename file) (helm-basedir dest-file))
    (rename-file file dest-file)
    (message "Restoring %s to %s done" (helm-basename file) (helm-basedir dest-file))
    (delete-file info-file)))

(defun helm-ff-trash-file-p (file)
  "Return t when FILE is a trashed file."
  (and (file-exists-p file)
       (string-match "Trash/files/?\\'" (helm-basedir file))
       (not (member (helm-basename file) '("." "..")))))

(defun helm-ff--get-dest-file-from-trash (trashed-files file)
  (assoc-default (helm-basename file) trashed-files))

(defun helm-ff-trash-list ()
  "Return an alist of trashed files basename and dest name."
  (cl-loop for f in (directory-files
                     (expand-file-name
                      ;; helm-ff-default-directory is actually the
                      ;; trash directory.
                      "info" (helm-basedir (directory-file-name helm-ff-default-directory)))
                     t directory-files-no-dot-files-regexp)
           collect (cons (helm-basename (replace-regexp-in-string "\\.trashinfo\\'" "" f))
                         (with-temp-buffer
                           (save-excursion
                             (insert-file-contents f))
                           (when (re-search-forward "^path=" nil t)
                             (helm-url-unhex-string
                              (buffer-substring-no-properties
                               (point) (point-at-eol))))))))

(defun helm-ff-goto-linum (candidate)
  "Find file CANDIDATE and maybe jump to line number found in fname at point.
Line number should be added at end of fname preceded with \":\".
E.g. \"foo:12\"."
  (let ((linum (with-helm-current-buffer
                 (let ((str (buffer-substring-no-properties
                             (point-at-bol) (point-at-eol))))
                   (when (string-match ":\\([0-9]+:?\\)" str)
                     (match-string 1 str))))))
    (find-file candidate)
    (and linum (not (string= linum ""))
         (helm-goto-line (string-to-number linum) t))))

(defun helm-ff-mail-attach-files (_candidate)
  "Run `mml-attach-file' on `helm-marked-candidates'."
  (require 'mml)
  (let ((flist (helm-marked-candidates :with-wildcard t))
        (dest-buf (and (derived-mode-p 'message-mode 'mail-mode)
                       (current-buffer)))
        bufs)
    (unless dest-buf
      (setq bufs (cl-loop for b in (buffer-list)
                          when (with-current-buffer b
                                 (derived-mode-p 'message-mode 'mail-mode))
                          collect (buffer-name b)))
      (if (and bufs (y-or-n-p "Attach files to existing mail composition buffer? "))
          (setq dest-buf
                (if (cdr bufs)
                    (helm-comp-read "Attach to buffer: " bufs :nomark t)
                  (car bufs)))
        (compose-mail)
        (setq dest-buf (current-buffer))))
    (switch-to-buffer dest-buf)
    (save-restriction
      (widen)
      (save-excursion
        (goto-char (point-max))
        (cl-loop for f in flist
                 do (mml-attach-file f (or (mm-default-file-encoding f)
                                           "application/octet-stream")))))))

(defvar image-dired-display-image-buffer)
(defun helm-ff-rotate-current-image-1 (file num-arg)
  "Rotate current image at NUM-ARG degrees."
  (setq file (file-truename file))      ; For symlinked images.
  ;; When FILE is not an image-file, do nothing.
  (when (and (file-exists-p file)
             (string-match (image-file-name-regexp) file))
    (setq num-arg (if (string= helm-ff-rotate-image-program "exiftran")
                      (cl-case num-arg
                        (90  "-9")      ; 90 clockwise
                        (270 "-2"))     ; 270 clockwise == -90
                    (number-to-string num-arg)))
    (if (executable-find helm-ff-rotate-image-program)
        (let ((default-directory (file-name-directory file))
              (basename (helm-basename file)))
          (apply #'process-file helm-ff-rotate-image-program nil nil nil
                 (append helm-ff-rotate-image-switch
                         (list num-arg basename)))
          (when (buffer-live-p image-dired-display-image-buffer)
            (kill-buffer image-dired-display-image-buffer))
          (image-dired-display-image basename)
          (message nil)
          (display-buffer (get-buffer image-dired-display-image-buffer)))
      (error "%s not found" helm-ff-rotate-image-program))))

(defun helm-ff-rotate-image-left (candidate)
  "Rotate image file CANDIDATE left.
This affects directly file CANDIDATE."
  (helm-ff-rotate-current-image-1 candidate 270))

(defun helm-ff-rotate-image-right (candidate)
  "Rotate image file CANDIDATE right.
This affects directly file CANDIDATE."
  (helm-ff-rotate-current-image-1 candidate 90))

(defun helm-ff-rotate-left-persistent ()
  "Rotate image left without quitting helm."
  (interactive)
  (with-helm-alive-p
    (helm-attrset 'image-action1 'helm-ff-rotate-image-left)
    (helm-execute-persistent-action 'image-action1)))
(put 'helm-ff-rotate-left-persistent 'helm-only t)

(defun helm-ff-rotate-right-persistent ()
  "Rotate image right without quitting helm."
  (interactive)
  (with-helm-alive-p
    (helm-attrset 'image-action2 'helm-ff-rotate-image-right)
    (helm-execute-persistent-action 'image-action2)))
(put 'helm-ff-rotate-right-persistent 'helm-only t)

(defun helm-ff-exif-data (candidate)
  "Extract exif data from file CANDIDATE using `helm-ff-exif-data-program'."
  (if (and helm-ff-exif-data-program
           (executable-find helm-ff-exif-data-program))
      (shell-command-to-string (format "%s %s %s"
                                       helm-ff-exif-data-program
                                       helm-ff-exif-data-program-args
                                       candidate))
    (format "No program %s found to extract exif"
            helm-ff-exif-data-program)))

(cl-defun helm-find-files-persistent-action-if (candidate)
  "Open subtree CANDIDATE without quitting helm.
If CANDIDATE is not a directory expand CANDIDATE filename.
If CANDIDATE is alone, open file CANDIDATE filename.
That means:
First hit on C-j expands CANDIDATE, second hit opens file.
If a prefix arg is given or `helm-follow-mode' is on, then open
file."
  (let* ((follow        (or (helm-follow-mode-p)
                            helm--temp-follow-flag))
         (image-cand    (string-match-p (image-file-name-regexp) candidate))
         (new-pattern   (helm-get-selection))
         (num-lines-buf (with-current-buffer helm-buffer
                          (count-lines (point-min) (point-max))))
         (insert-in-minibuffer (lambda (fname)
                                   (with-selected-window (or (active-minibuffer-window)
                                                             (minibuffer-window))
                                     (unless follow
                                       (delete-minibuffer-contents)
                                       (set-text-properties 0 (length fname)
                                                            nil fname)
                                       (insert fname))))))
    (helm-attrset 'candidate-number-limit helm-ff-candidate-number-limit)
    (unless image-cand
      (when follow
        (helm-follow-mode -1)
        (cl-return-from helm-find-files-persistent-action-if
          (message "Helm-follow-mode allowed only on images, disabling"))))
    (cond ((and (helm-ff--invalid-tramp-name-p)
                (string-match helm-tramp-file-name-regexp candidate))
           (cons (lambda (_candidate)
                   ;; First hit insert hostname and
                   ;; second hit insert ":" and expand.
                   (if (string= candidate helm-pattern)
                       (funcall insert-in-minibuffer (concat candidate ":"))
                     (funcall insert-in-minibuffer candidate)))
                 'never-split))
          (;; A symlink directory, expand it but not to its truename
           ;; unless a prefix arg is given.
           (and (file-directory-p candidate) (file-symlink-p candidate))
           (cons (lambda (_candidate)
                   (funcall insert-in-minibuffer
                            (file-name-as-directory
                             (if current-prefix-arg
                                 (file-truename (expand-file-name candidate))
                               (expand-file-name candidate)))))
                 'never-split))
          ;; A directory, open it.
          ((file-directory-p candidate)
           (cons (lambda (_candidate)
                   (when (string= (helm-basename candidate) "..")
                     (setq helm-ff-last-expanded helm-ff-default-directory))
                   (funcall insert-in-minibuffer (file-name-as-directory
                                                  (expand-file-name candidate)))
                   (with-helm-after-update-hook (helm-ff-retrieve-last-expanded)))
                 'never-split))
          ;; A symlink file, expand to it's true name. (first hit)
          ((and (file-symlink-p candidate) (not current-prefix-arg) (not follow))
           (cons (lambda (_candidate)
                   (funcall insert-in-minibuffer (file-truename candidate))
                   (helm-check-minibuffer-input)) ; Force update.
                 'never-split))
          ;; A regular file, expand it, (first hit)
          ((and (>= num-lines-buf 3) (not current-prefix-arg) (not follow))
           (cons (lambda (_candidate)
                   (funcall insert-in-minibuffer new-pattern)
                   (helm-check-minibuffer-input)) ; Force update.
                 'never-split))
          ;; An image file and it is the second hit on C-j,
          ;; show the file in `image-dired'.
          (image-cand
           (lambda (_candidate)
             (require 'image-dired)
             (let* ((win (get-buffer-window
                          image-dired-display-image-buffer 'visible))
                    (fname (and win
                                (with-selected-window win
                                  (get-text-property (point-min)
                                                     'original-file-name))))
                    (remove-buf-only (and win
                                          fname
                                          (with-helm-buffer
                                            (file-equal-p candidate fname)))))
               (when remove-buf-only
                 (with-helm-window
                   (if (and helm-persistent-action-display-window
                            (window-dedicated-p (next-window win 1)))
                       (delete-window helm-persistent-action-display-window)
                     (set-window-buffer win helm-current-buffer))))
               (when (buffer-live-p (get-buffer image-dired-display-image-buffer))
                 (kill-buffer image-dired-display-image-buffer))
               (unless remove-buf-only
                 ;; Fix emacs bug never fixed upstream.
                 (unless (file-directory-p image-dired-dir)
                   (make-directory image-dired-dir))
                 (switch-to-buffer image-dired-display-image-buffer)
                 (message "Resizing image...")
                 (cl-letf (((symbol-function 'message) #'ignore))
                   (image-dired-display-image candidate))
                 (message "Resizing image done")
                 (with-current-buffer image-dired-display-image-buffer
                   (let ((exif-data (helm-ff-exif-data candidate)))
                     (setq default-directory helm-ff-default-directory)
                     (image-dired-update-property 'help-echo exif-data)))))))
          ;; Allow browsing archive on avfs fs.
          ;; Assume volume is already mounted with mountavfs.
          ((helm-aand helm-ff-avfs-directory
                      (file-name-directory candidate)
                      (string-match
                       (regexp-quote (expand-file-name helm-ff-avfs-directory))
                       it)
                      (helm-ff-file-compressed-p candidate))
           (cons (lambda (_candidate)
                   (funcall insert-in-minibuffer (concat candidate "#/")))
                 'never-split))
          ;; File doesn't exists and basename starts with ".." or "  ",
          ;; Start a recursive search for directories.
          ((and (not (file-exists-p candidate))
                (not (file-remote-p candidate))
                (string-match-p "\\`\\([.]\\|\\s-\\)\\{2\\}[^/]+"
                                (helm-basename candidate)))
           ;; As soon as the final "/" is added the job is passed
           ;; to `helm-ff-auto-expand-to-home-or-root'.
           (cons (lambda (_candidate)
                   (funcall insert-in-minibuffer (concat candidate "/")))
                 'never-split))
          ;; File is not existing and have no basedir, typically when
          ;; user hit C-k (minibuffer is empty) and then write foo and
          ;; hit C-j. This make clear that when no basedir, helm will
          ;; create the file in default-directory.
          ((and (not (file-exists-p candidate))
                (not (helm-basedir candidate)))
           (cons (lambda (_candidate)
                   (funcall insert-in-minibuffer
                            (expand-file-name candidate default-directory)))
                 'never-split))
          ;; On second hit we open file.
          ;; On Third hit we kill it's buffer maybe.
          (t
           (lambda (_candidate)
             (funcall helm-ff-kill-or-find-buffer-fname-fn candidate))))))


;;; Recursive dirs completion
;;
(defun helm-find-files-recursive-dirs (directory &optional input)
  (when (string-match "\\(\\s-+\\|[.]\\)\\{2\\}" input)
    (setq input (replace-match "" nil t input)))
  (message "Recursively searching %s from %s ..."
           input (abbreviate-file-name directory))
  ;; Ensure to not create a new frame
  (let (helm-actions-inherit-frame-settings)
    (helm :sources
          (helm-make-source
              "Recursive directories" 'helm-locate-subdirs-source
            :basedir (if (string-match-p
                          "\\`es" helm-locate-recursive-dirs-command)
                         directory
                       (shell-quote-argument directory))
            :subdir (shell-quote-argument input)
            :candidate-transformer
            `((lambda (candidates)
                (cl-loop for c in candidates
                         when (and (file-directory-p c)
                                   (null (helm-boring-directory-p
                                          c helm-boring-file-regexp-list))
                                   (string-match-p ,(regexp-quote input)
                                                   (helm-basename c)))
                         collect (propertize c 'face 'helm-ff-dirs)))
              helm-w32-pathname-transformer
              (lambda (candidates)
                (helm-ff-sort-candidates-1 candidates ,input)))
            :persistent-action 'ignore
            :action (lambda (c)
                      (helm-set-pattern
                       (file-name-as-directory (expand-file-name c)))))
          :candidate-number-limit 999999
          :allow-nest t
          :resume 'noresume
          :ff-transformer-show-only-basename nil
          :buffer "*helm recursive dirs*")))

(defun helm-ff-recursive-dirs (_candidate)
  "Launch a recursive search in `helm-ff-default-directory'."
  (with-helm-default-directory helm-ff-default-directory
      (helm-find-files-recursive-dirs
       (helm-current-directory)
       (helm-basename (helm-get-selection)))))

(defun helm-ff-file-compressed-p (candidate)
  "Whether CANDIDATE is a compressed file or not."
  (member (file-name-extension candidate)
          helm-ff-file-compressed-list))

(defun helm-ff--fname-at-point ()
  "Try to guess fname at point."
  (let ((end (point))
        (limit (helm-aif (bounds-of-thing-at-point 'filename)
                   (car it)
                 (point))))
    (save-excursion
      (while (re-search-backward "\\(~\\|/\\|[[:lower:][:upper:]]:/\\)"
                                 limit t))
      (buffer-substring-no-properties (point) end))))

(defun helm-insert-file-name-completion-at-point (_candidate)
  "Insert file name completion at point.

When completing i.e. there is already something at point, insert
filename abbreviated, relative or full according to initial
input, whereas when inserting i.e. there is nothing at point,
insert filename full, abbreviated or relative according to prefix
arg, respectively no prefix arg, one prefix arg or two prefix
arg."
  (with-helm-current-buffer
    (if buffer-read-only
        (error "Error: Buffer `%s' is read-only" (buffer-name))
      (let* ((mkds        (helm-marked-candidates :with-wildcard t))
             (candidate   (car mkds))
             (end         (point))
             (tap         (helm-ffap-guesser))
             (guess       (and (stringp tap)
                               (substring-no-properties tap)))
             (beg         (helm-aif (and guess
                                         (save-excursion
                                           (when (re-search-backward
                                                  (regexp-quote guess)
                                                  (point-at-bol) t)
                                             (point))))
                              it (point)))
             (full-path-p (and (stringp guess)
                               (or (string-match-p
                                    (concat "^" (getenv "HOME"))
                                    guess)
                                   (string-match-p
                                    "\\`\\(/\\|[[:lower:][:upper:]]:/\\)"
                                    guess))))
             (escape-fn (if (memq major-mode
                                  helm-modes-using-escaped-strings)
                            #'shell-quote-argument #'identity)))
        (when (and beg end)
          (delete-region beg end))
        (insert
         (funcall
          escape-fn
          (helm-ff--format-fname-to-insert
           candidate beg end full-path-p guess
           helm-current-prefix-arg))
         (if (cdr mkds) " " "")
         (mapconcat escape-fn
                    (cl-loop for f in (cdr mkds)
                             collect (helm-ff--format-fname-to-insert
                                      f nil nil nil nil
                                      helm-current-prefix-arg))
                    " "))))))

(defun helm-ff--format-fname-to-insert (candidate
                                        &optional beg end full-path guess prefarg)
  (set-text-properties 0 (length candidate) nil candidate)
  (if (and beg end guess (not (string= guess ""))
           (null prefarg)
           (or (string-match
                "^\\(~/\\|/\\|[[:lower:][:upper:]]:/\\)"
                guess)
               (file-exists-p candidate)))
      (cond (full-path
             (expand-file-name candidate))
            ((string= (match-string 1 guess) "~/")
             (abbreviate-file-name candidate))
            (t (file-relative-name candidate)))
    (helm-acase prefarg
      ('(4)  (abbreviate-file-name candidate))
      ('(16) (file-relative-name candidate))
      ('(64) (helm-basename candidate))
      (t candidate))))

(cl-defun helm-find-files-history (arg &key (comp-read t))
  "The `helm-find-files' history.
Show the first `helm-ff-history-max-length' elements of
`helm-ff-history' in an `helm-comp-read'."
  (interactive "p")
  (let ((history (when helm-ff-history
                   (helm-fast-remove-dups helm-ff-history
                                          :test 'equal))))
    (when history
      (setq helm-ff-history
            (if (>= (length history) helm-ff-history-max-length)
                (cl-subseq history 0 helm-ff-history-max-length)
              history))
      (if comp-read
          (let ((src (helm-build-sync-source "Helm Find Files History"
                       :candidates helm-ff-history
                       :fuzzy-match (helm-ff-fuzzy-matching-p)
                       :persistent-action 'ignore
                       :migemo t
                       :action (lambda (candidate)
                                 (if arg
                                     (helm-set-pattern
                                      (expand-file-name candidate))
                                   (identity candidate))))))
            (helm :sources src
                  :resume 'noresume
                  :buffer helm-ff-history-buffer-name
                  :allow-nest t))
        helm-ff-history))))
(put 'helm-find-files-history 'helm-only t)

(defun helm-find-files-1 (fname &optional preselect)
  "Find FNAME filename with PRESELECT filename preselected.

Use it for non-interactive calls of `helm-find-files'."
  (require 'tramp)
  ;; Resolve FNAME now outside of helm.
  ;; [FIXME] When `helm-find-files-1' is used directly from lisp
  ;; and FNAME is an abbreviated path, for some reasons
  ;; `helm-update' is called many times before resolving
  ;; the abbreviated path (Issue #1939) so be sure to pass a
  ;; full path to helm-find-files-1.
  (unless (string-match-p helm-ff-url-regexp fname)
    (setq fname (expand-file-name (substitute-in-file-name fname))))
  (when (get-buffer helm-action-buffer)
    (kill-buffer helm-action-buffer))
  (setq helm-find-files--toggle-bookmark nil)
  (let* ( ;; Be sure we don't erase the precedent minibuffer if some.
         (helm-ff-auto-update-initial-value
          (and helm-ff-auto-update-initial-value
               (not (minibuffer-window-active-p (minibuffer-window)))))
         (tap (thing-at-point 'filename))
         (def (and tap (or (file-remote-p tap)
                           (expand-file-name tap)))))
    (helm-set-local-variable 'helm-follow-mode-persistent nil)
    (unless helm-source-find-files
      (setq helm-source-find-files (helm-make-source
                                    "Find Files" 'helm-source-ffiles)))
    (when (helm-attr 'follow helm-source-find-files)
      (helm-attrset 'follow -1 helm-source-find-files))
    (helm-ff-setup-update-hook)
    (add-hook 'helm-resume-after-hook 'helm-ff--update-resume-after-hook)
    (unwind-protect
         (helm :sources 'helm-source-find-files
               :input fname
               :case-fold-search helm-file-name-case-fold-search
               :preselect preselect
               :ff-transformer-show-only-basename
               helm-ff-transformer-show-only-basename
               :default def
               :prompt "Find files or url: "
               :buffer "*helm find files*")
      (helm-ff--update-resume-after-hook nil t)
      (setq helm-ff-default-directory nil))))

(defun helm-ff--update-resume-after-hook (sources &optional nohook)
  "Meant to be used in `helm-resume-after-hook'.
When NOHOOK is non-nil run inconditionally, otherwise only when
source is `helm-source-find-files'."
  (when (or nohook (string= "Find Files"
                            (assoc-default 'name (car sources))))
    (helm-attrset 'resume `(lambda ()
                             (helm-ff-setup-update-hook)
                             (setq helm-ff-default-directory
                                   ,helm-ff-default-directory
                                   helm-ff-last-expanded
                                   ,helm-ff-last-expanded))
                  helm-source-find-files)))

(defun helm-ff-clean-initial-input ()
  ;; When using hff in an external frame initial input is printed in
  ;; the minibuffer of initial-frame, delete it.
  (with-selected-frame helm-initial-frame
    (helm-clean-up-minibuffer)))

(defun helm-ff-setup-update-hook ()
  (dolist (hook '(helm-ff-clean-initial-input ; Add to be called first.
                  helm-ff-move-to-first-real-candidate
                  helm-ff-update-when-only-one-matched
                  helm-ff-auto-expand-to-home-or-root))
    (add-hook 'helm-after-update-hook hook)))

(defun helm-find-files-cleanup ()
  (mapc (lambda (hook)
          (remove-hook 'helm-after-update-hook hook))
        '(helm-ff-auto-expand-to-home-or-root
          helm-ff-update-when-only-one-matched
          helm-ff-move-to-first-real-candidate
          helm-ff-clean-initial-input)))

(defun helm-ff-bookmark ()
  (helm :sources 'helm-source-bookmark-helm-find-files
        :buffer "*helm ff bookmarks*"))

(defun helm-find-files-switch-to-bookmark ()
  "Switch to helm-bookmark for `helm-find-files' from `helm-find-files.'"
  (interactive)
  (require 'helm-bookmark)
  (with-helm-alive-p
    (helm-run-after-exit 'helm-ff-bookmark)))
(put 'helm-find-files-switch-to-bookmark 'helm-only t)

(defun helm-find-files-initial-input (&optional input)
  "Return INPUT if present, otherwise try to guess it."
  (let ((guesser (helm-acase (helm-ffap-guesser)
                   ("" nil)
                   (t it))))
    (unless (eq major-mode 'image-mode)
      (or (and input (or (and (file-remote-p input) input)
                         (expand-file-name input)))
          (helm-find-files-input
           (if (and helm-ff-allow-non-existing-file-at-point
                    guesser
                    (not (string-match ffap-url-regexp guesser)))
               ;; Keep the ability of jumping to numbered lines even
               ;; when allowing non existing filenames at point.
               (helm-aand guesser
                          (thing-at-point 'filename)
                          (replace-regexp-in-string
                           ":[0-9]+\\'" "" it))
             guesser)
           (thing-at-point 'filename))))))

(defun helm-ffap-guesser ()
  "Same as `ffap-guesser' but without gopher and machine support."
  (require 'ffap)
  ;; Avoid "Stack overflow in regexp matcher" error
  ;; in evil `ffap-guesser' by removing crap `ffap-gopher-at-point'
  ;; (bug fixed in emacs-26 #25391) .
  ;; `ffap-machine-at-point' have been removed too as it was anyway
  ;; disabled with `ffap-machine-p-known' bound to 'reject.
  ;; `ffap-file-at-point' can be neutralized with
  ;; `helm-ff-guess-ffap-filenames' and `ffap-url-at-point' with
  ;; `helm-ff-guess-ffap-urls'
  ;; Note also that `ffap-url-unwrap-remote' can override these
  ;; variables.
  (let ((ffap-alist (and helm-ff-guess-ffap-filenames ffap-alist))
        (ffap-url-regexp helm--url-regexp))
    (if (eq major-mode 'dired-mode)
        (let ((beg  (save-excursion (dired-move-to-filename)))
              (end  (save-excursion (dired-move-to-end-of-filename t))))
          (helm-aif (and beg end (member (buffer-substring beg end)
                                         '("." "..")))
              (concat (file-name-as-directory
                       (expand-file-name dired-directory))
                      (car it))
            (dired-get-filename 'no-dir t)))
      (let* ((beg (and (use-region-p) (region-beginning)))
             (end (and (use-region-p) (region-end)))
             (str (and beg end (buffer-substring-no-properties beg end)))
             (ffap (or (helm-aand helm-ff-guess-ffap-urls ffap-url-regexp
                                  (ffap-fixup-url (ffap-url-at-point))
                                  (and (string-match ffap-url-regexp it) it))
                       (ffap-file-at-point))))
        ;; Workaround emacs bugs:
        ;; When the region is active and a file is detected
        ;; `ffap-string-at-point' returns the region prefixed with
        ;; "/", e.g. at a beginning of a patch (first bug) and make
        ;; `file-remote-p' returning an error (second bug), so in such
        ;; case returns the region itself instead of the region
        ;; corrupted by ffap.
        (if (and str ffap) str ffap)))))

(defun helm-find-files-input (file-at-pt thing-at-pt)
  "Try to guess a default input for `helm-find-files'."
  (let* ((non-essential t)
         (remp    (or (and file-at-pt (file-remote-p file-at-pt))
                      (and thing-at-pt (file-remote-p thing-at-pt))))
         (def-dir (helm-current-directory))
         (urlp    (and file-at-pt helm--url-regexp
                       (string-match helm--url-regexp file-at-pt)))
         (lib     (when helm-ff-search-library-in-sexp
                    (helm-find-library-at-point)))
         (hlink   (helm-ff-find-url-at-point))
         (file-p  (and file-at-pt
                       (not (string= file-at-pt ""))
                       (not remp)
                       (or (file-exists-p file-at-pt)
                           helm-ff-allow-non-existing-file-at-point)
                       (not urlp)
                       thing-at-pt
                       (not (string= thing-at-pt ""))
                       (file-exists-p
                        (file-name-directory
                         (expand-file-name thing-at-pt def-dir))))))
    (cond (lib)      ; e.g we are inside a require sexp.
          (hlink)    ; String at point is an hyperlink.
          (file-p    ; a regular file
           (and file-at-pt (if (not (member (helm-basename file-at-pt)
                                            '("." "..")))
                               (expand-file-name file-at-pt)
                             file-at-pt)))
          (urlp (helm-html-decode-entities-string file-at-pt)) ; possibly an url or email.
          ((and file-at-pt
                (not remp)
                (or helm-ff-allow-non-existing-file-at-point
                    (file-exists-p file-at-pt)))
           (expand-file-name file-at-pt)))))

(defun helm-ff-find-url-at-point ()
  "Try to find link to an url in text-property at point."
  (let* ((he      (get-text-property (point) 'help-echo))
         (ov      (overlays-at (point)))
         (ov-he   (and ov (overlay-get
                           (car (overlays-at (point))) 'help-echo)))
         (w3m-l   (get-text-property (point) 'w3m-href-anchor))
         (nt-prop (get-text-property (point) 'nt-link)))
    ;; Org link.
    (when (and (stringp he) (string-match "^LINK: " he))
      (setq he (replace-match "" t t he)))
    (cl-loop for i in (list he ov-he w3m-l nt-prop)
          thereis (and (stringp i) helm--url-regexp (string-match helm--url-regexp i) i))))

(defun helm-find-library-at-point ()
  "Try to find library path at point.
Find inside `require' and `declare-function' sexp."
  (require 'find-func)
  (let* ((beg-sexp (save-excursion (search-backward "(" (point-at-bol) t)))
         (end-sexp (save-excursion (search-forward ")" (point-at-eol) t)))
         (sexp     (and beg-sexp end-sexp
                        (buffer-substring-no-properties
                         (1+ beg-sexp) (1- end-sexp)))))
    (ignore-errors
      (cond ((and sexp (string-match "require ['].+[^)]" sexp))
             (find-library-name
              (replace-regexp-in-string
               "'\\|)\\|(" ""
               ;; If require use third arg, ignore it,
               ;; always use library path found in `load-path'.
               (cl-second (split-string (match-string 0 sexp))))))
            ((and sexp (string-match-p "^declare-function" sexp))
             (find-library-name
              (replace-regexp-in-string
               "\"\\|ext:" ""
               (cl-third (split-string sexp)))))
            (t nil)))))


;;; Handle copy, rename, symlink, relsymlink and hardlink from helm.
;;
;;
(defun helm-ff--valid-default-directory ()
  (with-helm-current-buffer
    (cl-loop for b in (buffer-list)
             for cd = (with-current-buffer b default-directory)
             when (eq (car (file-attributes cd)) t)
             return cd)))

(cl-defun helm-dired-action (candidate
                             &key action follow (files (dired-get-marked-files)))
  "Execute ACTION on FILES to CANDIDATE.
Where ACTION is a symbol that can be one of:
'copy, 'rename, 'symlink,'relsymlink, 'hardlink or 'backup.
Argument FOLLOW when non-nil specifies to follow FILES to
destination for the actions copy and rename."
  (require 'dired-async)
  (require 'dired-x) ; For dired-keep-marker-relsymlink
  (when (get-buffer dired-log-buffer) (kill-buffer dired-log-buffer))
  ;; When default-directory in current-buffer is an invalid directory,
  ;; (e.g buffer-file directory have been renamed somewhere else)
  ;; be sure to use a valid value to give to dired-create-file.
  ;; i.e start-process is creating a process buffer based on default-directory.
  (let ((default-directory (helm-ff--valid-default-directory))
        (fn     (cl-case action
                  (copy       'dired-copy-file)
                  (rename     'dired-rename-file)
                  (symlink    'make-symbolic-link)
                  (relsymlink 'dired-make-relative-symlink)
                  (hardlink   'dired-hardlink)
                  (backup     'backup-file)))
        (marker (cl-case action
                  ((copy rename backup) dired-keep-marker-copy)
                  (symlink              dired-keep-marker-symlink)
                  (relsymlink           dired-keep-marker-relsymlink)
                  (hardlink             dired-keep-marker-hardlink)))
        (dirflag (and (= (length files) 1)
                      (file-directory-p (car files))
                      (not (file-directory-p candidate))))
        (dired-async-state (if (and (boundp 'dired-async-mode)
                                    dired-async-mode)
                               1 -1)))
    (and follow (fboundp 'dired-async-mode) (dired-async-mode -1))
    (when (and (cdr files) (not (file-directory-p candidate)))
      (error "%s: target `%s' is not a directory" action candidate))
    (unwind-protect
         (dired-create-files
          fn (symbol-name action) files
          ;; CANDIDATE is the destination.
          (if (file-directory-p candidate)
              ;; When CANDIDATE is a directory, build file-name in this directory.
              ;; Else we use CANDIDATE.
              (lambda (from)
                  (expand-file-name (file-name-nondirectory from) candidate))
              (lambda (_from) candidate))
          marker)
      (and (fboundp 'dired-async-mode)
           (dired-async-mode dired-async-state)))
    (push (file-name-as-directory
           (if (file-directory-p candidate)
               (expand-file-name candidate)
             (file-name-directory candidate)))
          helm-ff-history)
    ;; If follow is non--nil we should not be in async mode.
    (when (and follow
               (not (memq action '(symlink relsymlink hardlink)))
               (not (get-buffer dired-log-buffer)))
      (let ((target (directory-file-name candidate)))
        (unwind-protect
             (progn
               (setq helm-ff-cand-to-mark
                     (helm-get-dest-fnames-from-list files candidate dirflag))
               (with-helm-after-update-hook (helm-ff-maybe-mark-candidates))
               (if (and dirflag (eq action 'rename))
                   (helm-find-files-1 (file-name-directory target)
                                      (if helm-ff-transformer-show-only-basename
                                          (helm-basename target) target))
                 (helm-find-files-1 (file-name-as-directory
                                     (expand-file-name candidate)))))
          (setq helm-ff-cand-to-mark nil))))))

(defun helm-get-dest-fnames-from-list (flist dest-cand rename-dir-flag)
  "Transform filenames of FLIST to abs of DEST-CAND.
If RENAME-DIR-FLAG is non-nil collect the `directory-file-name'
of transformed members of FLIST."
  ;; At this point files have been renamed/copied at destination.
  ;; That's mean DEST-CAND exists.
  (cl-loop
        with dest = (expand-file-name dest-cand)
        for src in flist
        for basename-src = (helm-basename src)
        for fname = (cond (rename-dir-flag (directory-file-name dest))
                          ((file-directory-p dest)
                           (concat (file-name-as-directory dest) basename-src))
                          (t dest))
        when (file-exists-p fname)
        collect fname into tmp-list
        finally return (sort tmp-list 'string<)))

(defun helm-ff-maybe-mark-candidates ()
  "Mark all candidates of list `helm-ff-cand-to-mark'.
This is used when copying/renaming/symlinking etc. and following
files to destination."
  (when (and (string= (assoc-default 'name (helm-get-current-source))
                      (assoc-default 'name helm-source-find-files))
             helm-ff-cand-to-mark)
    (with-helm-window
      (while helm-ff-cand-to-mark
        (if (string= (car helm-ff-cand-to-mark) (helm-get-selection))
            (progn
              (helm-make-visible-mark)
              (helm-next-line)
              (setq helm-ff-cand-to-mark (cdr helm-ff-cand-to-mark)))
          (helm-next-line)))
      (unless (helm-this-visible-mark)
        (helm-prev-visible-mark)))))


;;; Routines for files
;;
;;
(defun helm-file-buffers (filename)
  "Return a list of buffer names corresponding to FILENAME."
  (cl-loop with name = (expand-file-name filename)
        for buf in (buffer-list)
        for bfn = (buffer-file-name buf)
        when (and bfn (string= name bfn))
        collect (buffer-name buf)))

(defun helm-ff--delete-by-moving-to-trash (file)
  "Decide to trash or delete FILE.
Return non-nil when FILE needs to be trashed."
  (let ((remote (file-remote-p file)))
    (or
     (and delete-by-moving-to-trash
          (null helm-current-prefix-arg)
          (null current-prefix-arg)
          (or (and remote helm-trash-remote-files)
              (null remote)))
     (and (null delete-by-moving-to-trash)
          (or helm-current-prefix-arg
              current-prefix-arg)
          (or (and remote helm-trash-remote-files)
              (null remote))))))

(defun helm-ff-quick-delete (_candidate)
  "Delete file CANDIDATE without quitting.

When a prefix arg is given, meaning of
`delete-by-moving-to-trash' is the opposite."
  (with-helm-window
    (let ((marked (helm-marked-candidates)))
      (unwind-protect
           (cl-loop with trash = (helm-ff--delete-by-moving-to-trash (car marked))
                    for c in marked do
                    (progn (helm-preselect
                            (concat "^" (regexp-quote
                                         (if (and helm-ff-transformer-show-only-basename
                                                  (not (helm-ff-dot-file-p c)))
                                             (helm-basename c) c))))
                           (when (y-or-n-p
                                  (format "Really %s file `%s'? "
                                          (if trash "Trash" "Delete")
                                          (abbreviate-file-name c)))
                             (helm-delete-file
                              c helm-ff-signal-error-on-dot-files 'synchro trash)
                             (helm-delete-current-selection)
                             (message nil)
                             (helm--remove-marked-and-update-mode-line c))))
        (setq helm-marked-candidates nil
              helm-visible-mark-overlays nil)
        (helm-force-update
         (let ((presel (helm-get-selection)))
           (when presel
             (concat "^" (regexp-quote (if (and helm-ff-transformer-show-only-basename
                                                (not (helm-ff-dot-file-p presel)))
                                           (helm-basename presel) presel))))))))))

(defun helm-delete-file (file &optional error-if-dot-file-p synchro trash)
  "Delete FILE after querying the user.

When a prefix arg is given, meaning of
`delete-by-moving-to-trash' is the opposite.

Return error when ERROR-IF-DOT-FILE-P is non-nil and user tries
to delete a dotted file i.e. \".\" or \"..\".

Ask user when directory are not empty to allow recursive deletion
unless `helm-ff-allow-recursive-deletes' is non nil.
When user is asked and reply with \"!\" don't ask for remaining
directories.

Ask to kill buffers associated with that file, too.

When TRASH is non nil, trash FILE even if `delete-by-moving-to-trash'
is nil."
  (require 'dired)
  (cl-block nil
    (when (and error-if-dot-file-p
               (helm-ff-dot-file-p file))
      (error "Error: Cannot operate on `.' or `..'"))
    (let ((buffers (helm-file-buffers file))
          (helm--reading-passwd-or-string t)
          (file-attrs (file-attributes file))
          (trash (or trash (helm-ff--delete-by-moving-to-trash file)))
          (delete-by-moving-to-trash trash))
      (cond ((and (eq (nth 0 file-attrs) t)
                  (directory-files file t dired-re-no-dot))
             ;; Synchro means persistent deletion from HFF.
             (if synchro
                 (when (or helm-ff-allow-recursive-deletes
                           trash
                           (y-or-n-p (format "Recursive delete of `%s'? "
                                             (abbreviate-file-name file))))
                   (delete-directory file 'recursive trash))
               ;; Avoid using dired-delete-file really annoying in
               ;; emacs-26 but allows using ! (instead of all) to not
               ;; confirm anymore for recursive deletion of
               ;; directory. This is not persistent for all session
               ;; like emacs-26 does with dired-delete-file (think it
               ;; is a bug).
               (if (or helm-ff-allow-recursive-deletes trash)
                   (delete-directory file 'recursive trash)
                 (helm-acase (helm-read-answer (format "Recursive delete of `%s'? [y,n,!,q]"
                                                      (abbreviate-file-name file))
                                              '("y" "n" "!" "q"))
                   ("y" (delete-directory file 'recursive trash))
                   ("!" (setq helm-ff-allow-recursive-deletes t)
                         (delete-directory file 'recursive trash))
                   ("n" (cl-return 'skip))
                   ("q" (throw 'helm-abort-delete-file
                           (progn
                             (message "Abort file deletion") (sleep-for 1))))))))
            ((eq (nth 0 file-attrs) t)
             (delete-directory file nil trash))
            (t (delete-file file trash)))
      (when buffers
        (cl-dolist (buf buffers)
          (when (y-or-n-p (format "Kill buffer %s, too? " buf))
            (kill-buffer buf)))))))

(defun helm-delete-marked-files (_ignore)
  "Delete marked files with `helm-delete-file'.

When a prefix arg is given, meaning of
`delete-by-moving-to-trash' is the opposite."
  (let* ((files (helm-marked-candidates :with-wildcard t))
         (len 0)
         (trash (helm-ff--delete-by-moving-to-trash (car files)))
         (prmt (if trash "Trash" "Delete"))
         (old--allow-recursive-deletes helm-ff-allow-recursive-deletes))
    (with-helm-display-marked-candidates
      helm-marked-buffer-name
      (helm-ff--count-and-collect-dups files)
      (if (not (y-or-n-p (format "%s *%s File(s)" prmt (length files))))
          (message "(No deletions performed)")
        (catch 'helm-abort-delete-file
          (unwind-protect
               (cl-dolist (i files)
                 (set-text-properties 0 (length i) nil i)
                 (let ((res (helm-delete-file
                             i helm-ff-signal-error-on-dot-files nil trash)))
                   (if (eq res 'skip)
                       (progn (message "Directory is not empty, skipping")
                              (sleep-for 1))
                     (cl-incf len))))
            (setq helm-ff-allow-recursive-deletes old--allow-recursive-deletes)))
        (message "%s File(s) %s" len (if trash "trashed" "deleted"))))))

;;; Delete files async
;;
;;
(defvar helm-ff-delete-log-file
  (locate-user-emacs-file "helm-delete-file.log")
  "The file use to communicate with Emacs child when deleting files async.")

(defvar helm-ff--trash-flag nil)

(define-minor-mode helm-ff--delete-async-modeline-mode
    "Notify mode-line that an async process run."
  :group 'dired-async
  :global t
  ;; FIXME: Handle jobs like in dired-async, needs first to allow
  ;; naming properly processes in async, they are actually all named
  ;; emacs and running `async-batch-invoke', so if one copy a file and
  ;; delete another file at the same time it may clash.
  :lighter (:eval (propertize (format " %s file(s) async ..."
                                      (if helm-ff--trash-flag
                                          "Trashing" "Deleting"))
                              'face 'helm-delete-async-message))
  (unless helm-ff--delete-async-modeline-mode
    (let ((visible-bell t)) (ding))
    (setq helm-ff--trash-flag nil)))

(defun helm-delete-async-mode-line-message (text face &rest args)
  "Notify end of async operation in mode-line."
  (message nil)
  (let ((mode-line-format (concat
                           " " (propertize
                                (if args
                                    (apply #'format text args)
                                    text)
                                'face face))))
    (force-mode-line-update)
    (sit-for 3)
    (force-mode-line-update)))

(defun helm-delete-marked-files-async (_ignore)
  "Same as `helm-delete-marked-files' but async.

When a prefix arg is given, meaning of
`delete-by-moving-to-trash' is the opposite.

This function is not using `helm-delete-file' and BTW not asking
user for recursive deletion of directory, be warned that
directories are always deleted with no warnings."
  (let* ((files (helm-marked-candidates :with-wildcard t))
         (trash (helm-ff--delete-by-moving-to-trash (car files)))
         (prmt (if trash "Trash" "Delete"))
         (buffers (cl-loop for file in files
                           for buf = (helm-file-buffers file)
                           when buf append buf))
         (callback (lambda (result)
                     (helm-ff--delete-async-modeline-mode -1)
                     (when (file-exists-p helm-ff-delete-log-file)
                       (display-warning 'helm
                                        (with-temp-buffer
                                          (insert-file-contents
                                           helm-ff-delete-log-file)
                                          (buffer-string))
                                        :error
                                        "*helm delete files*")
                       (fit-window-to-buffer (get-buffer-window
                                              "*helm delete files*"))
                       (delete-file helm-ff-delete-log-file))
                     (when buffers
                       (dolist (buf buffers)
                         (let ((last-nonmenu-event t))
                           (when (y-or-n-p (format "Kill buffer %s, too? " buf))
                             (kill-buffer buf)))))
                     (run-with-timer
                      0.1 nil
                      (lambda ()
                        (helm-delete-async-mode-line-message
                         "%s (%s/%s) file(s) async done"
                         'helm-delete-async-message
                         (if trash "Trashing" "Deleting")
                         result (length files))))))
         ;; Workaround emacs-26 bug with tramp see
         ;; https://github.com/jwiegley/emacs-async/issues/80.
         (async-quiet-switch "-q"))
    (setq helm-ff--trash-flag trash)
    (with-helm-display-marked-candidates
      helm-marked-buffer-name
      (helm-ff--count-and-collect-dups files)
      (if (not (y-or-n-p (format "%s *%s File(s)" prmt (length files))))
          (message "(No deletions performed)")
        (async-start
         `(lambda ()
            ;; `delete-by-moving-to-trash' have to be set globally,
            ;; using the TRASH argument of delete-file or
            ;; delete-directory is not enough.
            (setq delete-by-moving-to-trash ,trash)
            (let ((result 0))
              (dolist (file ',files result)
                (condition-case err
                    (cond ((eq (nth 0 (file-attributes file)) t)
                           (delete-directory file 'recursive ,trash)
                           (setq result (1+ result)))
                          (t (delete-file file ,trash)
                             (setq result (1+ result))))
                  (error (with-temp-file ,helm-ff-delete-log-file
                           (insert (format-time-string "%x:%H:%M:%S\n"))
                           (insert (format "%s:%s\n"
                                           (car err)
                                           (mapconcat 'identity (cdr err) " ")))))))))
         callback)
        (helm-ff--delete-async-modeline-mode 1)))))

(defun helm-find-file-or-marked (candidate)
  "Open file CANDIDATE or open helm marked files in separate windows.
Called with one prefix arg open files in separate windows in a
vertical split.
Called with two prefix arg open files in background without
selecting them."
  (let ((marked (helm-marked-candidates :with-wildcard t))
        (url-p (and helm--url-regexp ; we should have only one candidate.
                    (string-match helm--url-regexp candidate)))
        (ffap-newfile-prompt helm-ff-newfile-prompt-p)
        (find-file-wildcards nil)
        (helm--reading-passwd-or-string t))
    (if (cdr marked)
        (if (equal helm-current-prefix-arg '(16))
            (mapcar 'find-file-noselect marked)
          ;; If helm-current-prefix-arg is detected split is done
          ;; vertically.
          (helm-window-show-buffers (mapcar 'find-file-noselect marked)))
      (let ((dir (and (not url-p) (helm-basedir candidate))))
        (cond ((and dir (file-directory-p dir))
               (find-file (substitute-in-file-name candidate)))
              (url-p (find-file-at-point candidate))
              ;; A a non--existing filename ending with /
              ;; Create a directory and jump to it.
              ((and (not (file-exists-p candidate))
                    (string-match "/$" candidate))
               (helm-ff--mkdir candidate 'helm-ff))
              ;; A non--existing filename NOT ending with / or
              ;; an existing filename, create or jump to it.
              ;; If the basedir of candidate doesn't exists,
              ;; ask for creating it.
              (dir
               (helm-ff--mkdir dir)
               (find-file candidate))
              ;; Find file at `default-directory' when basedir is
              ;; unspecified e.g user hit C-k foo RET.
              (t (find-file candidate)))))))

(defun helm-ff-find-file-other-tab ()
  "Run find file in other tab action from `helm-source-buffers-list'."
  (interactive)
  (cl-assert (fboundp 'tab-bar-mode) nil "Tab-bar-mode not available")
  (with-helm-alive-p
    (helm-exit-and-execute-action 'find-file-other-tab)))
(put 'helm-ff-find-file-other-tab 'helm-only t)

(defun helm-ff--mkdir (dir &optional helm-ff)
  (when (or (not confirm-nonexistent-file-or-buffer)
            (y-or-n-p (format "Create directory `%s'? "
                              (abbreviate-file-name
                               (expand-file-name dir)))))
    (let ((dirfname (directory-file-name dir)))
      (if (file-exists-p dirfname)
          (error
           "Mkdir: Unable to create directory `%s': file exists."
           (helm-basename dirfname))
        (make-directory dir 'parent)))
    (when helm-ff
      ;; Allow having this new dir in history
      ;; to be able to retrieve it immediately
      ;; if we want to e.g copy a file from somewhere in it.
      (setq helm-ff-default-directory
            (file-name-as-directory (expand-file-name dir)))
      (push helm-ff-default-directory helm-ff-history))
    (or (and helm-ff (helm-find-files-1 dir)) t)))

(defun helm-transform-file-load-el (actions candidate)
  "Add action to load the file CANDIDATE if it is an Emacs Lisp
file.  Else return ACTIONS unmodified."
  (if (member (file-name-extension candidate) '("el" "elc"))
      (append actions '(("Load Emacs Lisp File" . load-file)))
    actions))

(defun helm-transform-file-browse-url (actions candidate)
  "Add an action to browse the file CANDIDATE if it is a HTML file or URL.
Else return ACTIONS unmodified."
  (let ((browse-action '("Browse with Browser" . browse-url)))
    (cond ((string-match "^http\\|^ftp" candidate)
           (cons browse-action actions))
          ((string-match "\\.html?$" candidate)
           (append actions (list browse-action)))
          (t actions))))

(defun helm-file-on-mounted-network-p (file)
  "Return non-nil when FILE is part of a mounted remote directory.

This function is checking `helm-mounted-network-directories'
list."
  (when helm-mounted-network-directories
    (cl-loop for dir in helm-mounted-network-directories
             thereis (file-in-directory-p file dir))))

;; helm-find-files bindings for filecache
(defvar file-cache-alist)

(defun helm-ff-cache-add-file (_candidate)
  (require 'filecache)
  (let ((mkd (helm-marked-candidates :with-wildcard t)))
    (mapc 'file-cache-add-file mkd)))

(defun helm-ff-file-cache-remove-file-1 (file)
  "Remove FILE from `file-cache-alist'."
  (let ((entry (assoc (helm-basename file) file-cache-alist))
        (dir   (helm-basedir file))
        new-entry)
    (setq new-entry (remove dir entry))
    (when (= (length entry) 1)
      (setq new-entry nil))
    (setq file-cache-alist
          (cons new-entry (remove entry file-cache-alist)))))

(defun helm-ff-file-cache-remove-file (_file)
  "Remove marked files from `file-cache-alist.'"
  (let ((mkd (helm-marked-candidates)))
    (mapc 'helm-ff-file-cache-remove-file-1 mkd)))


;;; File name history
;;
;;
(defvar helm-source-file-name-history
  (helm-build-sync-source "File Name History"
    :candidates 'file-name-history
    :persistent-action #'ignore
    :filtered-candidate-transformer #'helm-file-name-history-transformer
    :action 'helm-type-file-actions))

(defvar helm-source--ff-file-name-history nil
  "[INTERNAL] This source is build to be used with `helm-find-files'.
Don't use it in your own code unless you know what you are
doing.")

(defvar helm--file-name-history-hide-deleted nil)

(defun helm-file-name-history-show-or-hide-deleted ()
  (interactive)
  (setq helm--file-name-history-hide-deleted
        (not helm--file-name-history-hide-deleted))
  (helm-update))
(put 'helm-file-name-history-show-or-hide-deleted 'helm-only t)

(defvar helm-file-name-history-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map helm-map)
    (define-key map (kbd "C-c d")   'helm-file-name-history-show-or-hide-deleted)
    (define-key map (kbd "C-x C-f") 'helm-ff-file-name-history-run-ff)
    map))

(defun helm-file-name-history-transformer (candidates _source)
  (cl-loop for c in candidates
           when (cond ((or (file-remote-p c)
                           (and (fboundp 'tramp-archive-file-name-p)
                                (tramp-archive-file-name-p c)))
                       (cons (propertize c 'face 'helm-history-remote) c))
                      ((file-exists-p c)
                       (cons (propertize c 'face 'helm-ff-file) c))
                      (t (unless helm--file-name-history-hide-deleted
                           (cons (propertize c 'face 'helm-history-deleted) c))))
           collect it))

(defun helm-ff-file-name-history-ff (candidate)
  (helm-set-pattern
   (expand-file-name candidate)))

(defun helm-ff-file-name-history-run-ff ()
  "Switch back to current HFF session with selection as preselect."
  (interactive)
  (with-helm-alive-p
    (helm-exit-and-execute-action 'helm-ff-file-name-history-ff)))

(defun helm-ff-file-name-history ()
  "Switch to `file-name-history' without quitting `helm-find-files'."
  (interactive)
  (unless helm-source--ff-file-name-history
    (setq helm-source--ff-file-name-history
          (helm-build-sync-source "File name history"
            :init (lambda ()
                    (with-helm-alive-p
                      (require 'tramp-archive nil t)
                      (when helm-ff-file-name-history-use-recentf
                        (require 'recentf)
                        (or recentf-mode (recentf-mode 1)))))
            :candidates (lambda ()
                          (if helm-ff-file-name-history-use-recentf
                              recentf-list
                              file-name-history))
            :help-message 'helm-file-name-history-help-message
            :fuzzy-match t
            :persistent-action 'ignore
            :migemo t
            :filtered-candidate-transformer 'helm-file-name-history-transformer
            :action (helm-make-actions
                     "Find file" (lambda (candidate)
                                   (helm-set-pattern
                                    (expand-file-name candidate))
                                   (with-helm-after-update-hook (helm-exit-minibuffer)))
                     "Find file in helm" 'helm-ff-file-name-history-ff)
            :keymap helm-file-name-history-map)))
  (with-helm-alive-p
    (helm :sources 'helm-source--ff-file-name-history
          :buffer "*helm-file-name-history*"
          :allow-nest t
          :resume 'noresume)))
(put 'helm-ff-file-name-history 'helm-only t)

;;; Browse project
;; Need dependencies:
;; <https://github.com/emacs-helm/helm-ls-git>
;; <https://github.com/emacs-helm/helm-ls-hg>
;; Only hg and git are supported for now.
(defvar helm--browse-project-cache (make-hash-table :test 'equal))
(defvar helm-buffers-in-project-p)

(defvar helm-browse-project-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map helm-generic-files-map)
    (define-key map (kbd "M-g a") 'helm-browse-project-run-ag)
    map))
  
(defun helm-browse-project-get-buffers (root-directory)
  (cl-loop for b in (helm-buffer-list)
           ;; FIXME: Why default-directory is root-directory
           ;; for current-buffer when coming from helm-quit-and-find-file.
           for cd = (with-current-buffer b default-directory)
           for bn = (buffer-file-name (get-buffer b))
           if (or (and bn (file-in-directory-p bn root-directory))
                  (and (null bn)
                       (not (file-remote-p cd))
                       (file-in-directory-p cd root-directory)))
           collect b))

(defun helm-browse-project-build-buffers-source (directory)
  (helm-make-source "Buffers in project" 'helm-source-buffers
    :header-name (lambda (name)
                   (format
                    "%s (%s)"
                    name (abbreviate-file-name directory)))
    :buffer-list (lambda () (helm-browse-project-get-buffers directory))))

(defun helm-browse-project-walk-directory (directory)
  "Default function for `helm-browse-project-default-find-files-fn'."
  (helm-walk-directory
   directory
   :directories nil :path 'full :skip-subdirs t))

(defun helm-browse-project-find-files-1 (directory program)
  "List files in DIRECTORY recursively with external PROGRAM."
  (let ((cmd (cl-ecase program
               (ag "ag --hidden -g '.*' %s")
               (rg "rg --files --hidden -g '*' %s"))))
    (with-temp-buffer
      (call-process-shell-command
       (format cmd directory)
       nil t nil)
      (mapcar (lambda (f) (expand-file-name f directory))
              (split-string (buffer-string) "\n")))))

(defun helm-browse-project-ag-find-files (directory)
  "A suitable function for `helm-browse-project-default-find-files-fn'.
Use AG as backend."
  (helm-browse-project-find-files-1 directory 'ag))

(defun helm-browse-project-rg-find-files (directory)
  "A suitable function for `helm-browse-project-default-find-files-fn'.
Use RG as backend."
  (helm-browse-project-find-files-1 directory 'rg))

(defun helm-browse-project-ag (_candidate)
  "A `helm-grep' AG action for `helm-browse-project'."
  (let ((dir (with-helm-buffer (helm-attr 'root-dir))))
    (helm-grep-ag dir helm-current-prefix-arg)))

(defun helm-browse-project-run-ag ()
  "Run `helm-grep' AG from `helm-browse-project'."
  (interactive)
  (with-helm-alive-p
    (helm-exit-and-execute-action 'helm-browse-project-ag)))
(put 'helm-browse-project-run-ag 'helm-only t)

(defclass helm-browse-project-override-inheritor (helm-type-file) ())

(defclass helm-browse-project-source (helm-source-in-buffer
                                      helm-browse-project-override-inheritor)
  ((root-dir :initarg :root-dir
             :initform nil
             :custom 'file)
   (match-part :initform
               (lambda (c)
                 (if (with-helm-buffer
                       helm-ff-transformer-show-only-basename)
                     (helm-basename c) c)))
   (filter-one-by-one :initform
                      (lambda (c)
                        (if (with-helm-buffer
                              helm-ff-transformer-show-only-basename)
                            (cons (propertize (helm-basename c)
                                              'face 'helm-ff-file)
                                  c)
                          (propertize c 'face 'helm-ff-file)))))
  "Class to define a source in `helm-browse-project' handling non
VC handled directories.")

(defmethod helm--setup-source :after ((source helm-browse-project-override-inheritor))
  (let ((actions (slot-value source 'action)))
    (setf (slot-value source 'action)
          (helm-append-at-nth
           (symbol-value actions)
           '(("Grep project with AG `M-g a, C-u select type'" . helm-browse-project-ag))
           7))
    (setf (slot-value source 'keymap) helm-browse-project-map)))

(defun helm-browse-project-find-files (directory &optional refresh)
  "Browse non VC handled directory DIRECTORY."
  (when refresh (remhash directory helm--browse-project-cache))
  (unless (gethash directory helm--browse-project-cache)
    (puthash directory (funcall helm-browse-project-default-find-files-fn
                                directory)
             helm--browse-project-cache))
  (helm :sources `(,(helm-browse-project-build-buffers-source directory)
                   ,(helm-make-source "Browse project"
                        'helm-browse-project-source
                        :root-dir directory
                        :data (gethash directory helm--browse-project-cache)
                        :header-name
                        (lambda (name)
                          (format
                           "%s (%s)"
                           name (abbreviate-file-name directory)))))
        :ff-transformer-show-only-basename nil
        :buffer "*helm browse project*"))

(defvar helm-browse-project-history nil)

;;;###autoload
(defun helm-projects-history (arg)
  (interactive "P")
  (helm :sources
        (helm-build-sync-source "Project history"
          :candidates helm-browse-project-history
          :action (lambda (candidate)
                    (with-helm-default-directory candidate
                        (helm-browse-project
                         (or arg helm-current-prefix-arg)))))
        :buffer "*helm browse project history*"))

;;;###autoload
(defun helm-browse-project (arg)
  "Preconfigured helm to browse projects.
Browse files and see status of project with its VCS.
Only HG and GIT are supported for now.
Fall back to `helm-browse-project-find-files' if current
directory is not under control of one of those VCS.
With a prefix ARG browse files recursively, with two prefix ARG
rebuild the cache.
If the current directory is found in the cache, start
`helm-browse-project-find-files' even with no prefix ARG.
NOTE: The prefix ARG have no effect on the VCS controlled
directories.

Needed dependencies for VCS:
<https://github.com/emacs-helm/helm-ls-git>
and
<https://github.com/emacs-helm/helm-ls-hg>."
  (interactive "P")
  (require 'helm-x-files)
  (let ((helm-type-buffer-actions
         (remove (assoc "Browse project from buffer"
                        helm-type-buffer-actions)
                 helm-type-buffer-actions))
        (helm-buffers-in-project-p t))
    (cl-flet ((push-to-hist (root)
                (setq helm-browse-project-history
                      (cons root (delete root helm-browse-project-history)))))
      (helm-acond ((and (require 'helm-ls-git nil t)
                        (fboundp 'helm-ls-git-root-dir)
                        (helm-ls-git-root-dir))
                   (push-to-hist it)
                   (helm-ls-git-ls))
                  ((and (require 'helm-ls-hg nil t)
                        (fboundp 'helm-hg-root)
                        (helm-hg-root))
                   (push-to-hist it)
                   (helm-hg-find-files-in-project))
                  ((helm-browse-project-get--root-dir (helm-current-directory))
                   (if (or arg (gethash it helm--browse-project-cache))
                       (progn
                         (push-to-hist it)
                         (helm-browse-project-find-files it (equal arg '(16))))
                       (helm :sources (helm-browse-project-build-buffers-source it)
                             :buffer "*helm browse project*")))))))

(defun helm-browse-project-get--root-dir (directory)
  (cl-loop with dname = (file-name-as-directory directory)
           while (and dname (not (gethash dname helm--browse-project-cache)))
           if (file-remote-p dname)
           do (setq dname nil) else
           do (setq dname (helm-basedir (substring dname 0 (1- (length dname)))))
           finally return (or dname (file-name-as-directory directory))))

(defun helm-ff-browse-project (_candidate)
  "Browse project in current directory.
See `helm-browse-project'."
  (with-helm-default-directory helm-ff-default-directory
      (helm-browse-project helm-current-prefix-arg)))

(defun helm-ff-run-browse-project ()
  (interactive)
  (with-helm-alive-p
    (helm-exit-and-execute-action 'helm-ff-browse-project)))
(put 'helm-ff-run-browse-project 'helm-only t)

(defun helm-ff-gid (_candidate)
  (with-helm-default-directory helm-ff-default-directory
      (helm-gid)))

(defun helm-ff-run-gid ()
  (interactive)
  (with-helm-alive-p
    (helm-exit-and-execute-action 'helm-ff-gid)))
(put 'helm-ff-run-gid 'helm-only t)

;; helm-find bindings for helm-find-files.
(defun helm-ff-find-sh-command (_candidate)
  "Run `helm-find' from `helm-find-files'."
  (require 'helm-find)
  (helm-find-1 helm-ff-default-directory))

(defun helm-ff-run-find-sh-command ()
  "Run find shell command action with key from `helm-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-exit-and-execute-action 'helm-ff-find-sh-command)))
(put 'helm-ff-run-find-sh-command 'helm-only t)


;;;###autoload
(defun helm-find-files (arg)
  "Preconfigured `helm' for helm implementation of `find-file'.
Called with a prefix arg show history if some.
Don't call it from programs, use `helm-find-files-1' instead.
This is the starting point for nearly all actions you can do on
files."
  (interactive "P")
  (let* ((hist            (and arg helm-ff-history (helm-find-files-history nil)))
         (smart-input     (or hist (helm-find-files-initial-input)))
         (default-input   (expand-file-name (helm-current-directory)))
         (input           (cond ((and (null hist)
                                      helm-find-files-ignore-thing-at-point)
                                 default-input)
                                ((and (eq major-mode 'org-agenda-mode)
                                      org-directory
                                      (not smart-input))
                                 (file-name-as-directory
                                  (expand-file-name org-directory)))
                                ((and (eq major-mode 'dired-mode) smart-input)
                                 (file-name-directory smart-input))
                                ((and (not (string= smart-input ""))
                                      smart-input))
                                (t default-input)))
         (input-as-presel (null (nth 0 (file-attributes input))))
         (presel          (helm-aif (or hist
                                        (and input-as-presel input)
                                        (buffer-file-name (current-buffer))
                                        (and (eq major-mode 'dired-mode)
                                             smart-input))
                              (if (and helm-ff-transformer-show-only-basename
                                       (null hist)
                                       (not (string-match-p "[.]\\{1,2\\}\\'" it)))
                                  (helm-basename it) it))))
    ;; Continue using the same display function as history which used
    ;; probably itself the same display function as inner HFF call,
    ;; i.e. if history was using frame use a frame otherwise use a window.
    (when (and hist (buffer-live-p (get-buffer helm-ff-history-buffer-name)))
      (helm-set-local-variable 'helm-display-function
                               (with-current-buffer helm-ff-history-buffer-name
                                 helm-display-function)
                               'helm--last-frame-parameters
                               (with-current-buffer helm-ff-history-buffer-name
                                 helm--last-frame-parameters)))
    (set-text-properties 0 (length input) nil input)
    (setq current-prefix-arg nil)
    ;; Allow next helm session to reuse helm--last-frame-parameters as
    ;; resume would do.
    (let ((helm--executing-helm-action (not (null hist))))
      (helm-find-files-1 input (and presel (null helm-ff-no-preselect)
                                    (concat "^" (regexp-quote presel)))))))

;;;###autoload
(defun helm-delete-tramp-connection ()
  "Allow deleting tramp connection or marked tramp connections at once.

This replace `tramp-cleanup-connection' which is partially broken
in Emacs < to 25.1.50.1 (See Emacs Bug#24432).

It allows additionally to delete more than one connection at
once."
  (interactive)
  (let ((helm-quit-if-no-candidate
         (lambda ()
           (message "No Tramp connection found"))))
    (helm :sources (helm-build-sync-source "Tramp connections"
                     :candidates (tramp-list-connections)
                     :candidate-transformer (lambda (candidates)
                                              (cl-loop for v in candidates
                                                       for name = (apply #'tramp-make-tramp-file-name
                                                                         (cl-loop with v = (helm-ff--tramp-cons-or-vector v)
                                                                                  for i across v collect i))
                                                       when (or (processp (tramp-get-connection-process v))
                                                                (buffer-live-p (get-buffer (tramp-buffer-name v))))
                                                       collect (cons name v)))
                     :action (lambda (_vec)
                               (let ((vecs (helm-marked-candidates)))
                                 (cl-loop for v in vecs
                                          do (progn
                                               (tramp-cleanup-connection v)
                                               (remhash v tramp-cache-data))))))
          :buffer "*helm tramp connections*")))


(provide 'helm-files)

;; Local Variables:
;; byte-compile-warnings: (not obsolete)
;; coding: utf-8
;; indent-tabs-mode: nil
;; End:

;;; helm-files.el ends here
