;;; borg-elpa.el --- use Borg and Package.el alongside  -*- lexical-binding: t -*-

;; Copyright (C) 2017  Jonas Bernoulli

;; Author: Jonas Bernoulli <jonas@bernoul.li>
;; Homepage: https://github.com/emacscollective/borg
;; Keywords: tools

;; Package-Version: 2.0
;; Package-Requires: ((emacs "26.0") (borg "2.0") (dash "2.13") (epkg "3.0"))

;; This file contains code from GNU Emacs, which is
;; Copyright (C) 1976-2017 Free Software Foundation, Inc.

;; This file is not part of GNU Emacs.

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; For a full copy of the GNU General Public License
;; see https://www.gnu.org/licenses.

;;; Commentary:

;; This is only a proof-of-concept.

;; Use Borg and `package.el' alongside.

;; Eventually these use-cases should be supported.

;; 1. Only temporarily use for bugfix branches.
;;    - Install Borg from Melpa.
;;    - TODO Optionally activate clones, not just drones.
;;      This would avoid having to deal with submodules.
;; 2. Only use for packages the user contributes to.
;;    - Install Borg from Melpa.
;; 3. Evaluating Borg.
;;    - Probably install Borg from Melpa.
;; 4. Migrating to Borg.
;;    - TODO Document bootstrap process.
;; 5. Using two package managers is fun.

;; Assuming that the necessary packages have been installed using Borg
;; add this to `~/.emacs.d/init.el'.

;;  ;; (package-initialize) DO NOT REMOVE THIS NECESSARY COMMENT
;;  (add-to-list 'load-path (expand-file-name "lib/borg" user-emacs-directory))
;;  (require 'borg-elpa))

;; Installing Borg using `package.el' isn't supported yet.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(require 'borg)
(require 'package)

(eval-when-compile (require 'epkg))
(declare-function epkg 'epkg (name))

(defun borg-elpa-initialize ()
  "Initialize Borg and Elpa in the correct order."
  (add-to-list 'package-directory-list borg-drone-directory)
  (or (featurep 'epkg)
      (let ((load-path
             (nconc (mapcar (lambda (name)
                              (expand-file-name name borg-drone-directory))
                            '("dash" "finalize" "emacsql" "closql" "epkg"))
                    load-path)))
        (require 'epkg)))
  (package-initialize 'no-activate)
  (borg-initialize)
  (package-initialize))

(define-advice package-activate-1
    (:around (fn pkg-desc &optional reload deps) borg)
  "For a Borg-installed package, let Borg handle the activation."
  (unless (package--borg-clone-p (package-desc-dir pkg-desc))
    (funcall fn pkg-desc reload deps)))

(define-advice package-load-descriptor
    (:around (fn pkg-dir) borg)
  "For a Borg-installed package, use information from the Epkgs database."
  (if-let* ((dir (package--borg-clone-p pkg-dir)))
      (let* ((name (file-name-nondirectory (directory-file-name dir)))
             (epkg (epkg name))
             (desc (package-process-define-package
                    (list 'define-package
                          name
                          (borg--package-version name)
                          (if epkg
                              (or (oref epkg summary)
                                  "[No summary]")
                            "[Installed using Borg, but not in Epkgs database]")
                          ()))))
        (setf (package-desc-dir desc) pkg-dir)
        desc)
    (funcall fn pkg-dir)))

(defun package--borg-clone-p (pkg-dir)
  ;; Currently `pkg-dir' is a `directory-file-name', but that might change.
  (setq pkg-dir (file-name-as-directory pkg-dir))
  (and (equal (file-name-directory (directory-file-name pkg-dir))
              borg-drone-directory)
       pkg-dir))

(defvar borg--version-tag-glob "*[0-9]*")

(defun borg--package-version (clone)
  (or (and-let* ((version
                  (let ((default-directory (borg-worktree clone)))
                    (ignore-errors
                      (car (process-lines "git" "describe" "--tags"
                                          "--match" borg--version-tag-glob))))))
        (and (string-match
              "\\`\\(?:[^0-9]+\\)?\\([.0-9]+\\)\\(?:-\\([0-9]+-g\\)\\)?"
              version)
             (let ((version (version-to-list (match-string 1 version)))
                   (commits (match-string 2 version)))
               (when commits
                 (setq commits (string-to-number commits))
                 (setq version (seq-take version 3))
                 (when (< (length version) 3)
                   (setq version
                         (nconc version (make-list (- 3 (length version)) 0))))
                 (setq version
                       (nconc version (list commits))))
               (mapconcat #'number-to-string version "."))))
      "9999"))

(provide 'borg-elpa)
;; Local Variables:
;; indent-tabs-mode: nil
;; End:
;;; borg-elpa.el ends here
