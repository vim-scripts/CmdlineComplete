" Script Name: cmdline-complete.vim
" Version:     1.0.4
" Last Change: May 9, 2008
" Author:      Yuheng Xie <xie_yuheng@yahoo.com.cn>
"
" Description: complete command-line (: / etc.) from the current file
"
" Usage:       When editing the command-line, press <c-p> or <c-n> to complete
"              the word before the cursor, using keywords in the current file.
"
" Install:     Just drop this script file into vim's plugin directory.
"
"              If you want to use other keys instead of default <c-p> <c-n> to
"              trigger the completion, please say in your .vimrc
"                  cmap <c-y> <Plug>CmdlineCompleteBackward
"                  cmap <c-e> <Plug>CmdlineCompleteForward
"              this will use Ctrl-Y Ctrl-E for search backward and forward.
"
"              Without python, speed will be a bit slow with large file (e.g.
"              > 100K). Compile your vim with python is recommended.

" Anti reinclusion guards
if exists('g:loaded_cmdline_complete') && !exists('g:force_reload_cmdline_complete')
	finish
endif

" Support for |line-continuation|
let s:save_cpo = &cpo
set cpo&vim

" Default bindings

if !hasmapto('<Plug>CmdlineCompleteBackward', 'c')
	cmap <unique> <silent> <c-p> <Plug>CmdlineCompleteBackward
endif
if !hasmapto('<Plug>CmdlineCompleteForward', 'c')
	cmap <unique> <silent> <c-n> <Plug>CmdlineCompleteForward
endif

cnoremap <silent> <Plug>CmdlineCompleteBackward <c-r>=<sid>CmdlineComplete(1)<cr>
cnoremap <silent> <Plug>CmdlineCompleteForward  <c-r>=<sid>CmdlineComplete(0)<cr>

" Functions

" define variables if they don't exist
function! s:InitVariables()
	if !exists("s:seed")
		let s:seed = ""
		let s:completions = [""]
		let s:comp_i = 0
		let s:comp_max = 0
		let s:last_cmdline = ""
		let s:last_pos = 0
	endif
endfunction

" generate completion list in python
function! s:GenerateCompletionsPython(seed, backward)
	let completions_i2word = []

python << EOF
try:
	import sys, re, vim

	completions_i2word = []
	completions_word2i = set([])

	seed = vim.eval("a:seed")
	backward = int(vim.eval("a:backward"))

	regexp = re.compile(r'\b' + seed + r'\w+')
	if not seed:
		regexp = re.compile(r'\b\w\w+')
	elif re.search(r'\W', seed):
		regexp = re.compile(r'\b' + re.escape(seed) + r'\w+')

	buffer = vim.current.buffer
	cursor = vim.current.window.cursor
	wrapped = False

	r = range(cursor[0] - 1, len(buffer)) + range(0, cursor[0])
	if backward:
		r = range(cursor[0] - 1, -1, -1) + range(len(buffer) - 1, cursor[0] - 2, -1)
	for l in r:
		candidates = regexp.findall(buffer[l])
		if l == cursor[0] - 1:
			candidates = []
			m = regexp.search(buffer[l])
			while m:
				if backward and (not wrapped and m.start() <= cursor[1] \
						or wrapped and m.start() > cursor[1]) \
						or not backward and (wrapped and m.end() <= cursor[1] \
						or not wrapped and m.end() > cursor[1]):
					candidates.append(m.group())
				m = regexp.search(buffer[l], m.end())
			wrapped = True

		if candidates:
			if backward:
				for candidate in reversed(candidates):
					if candidate not in completions_word2i:
						completions_i2word.append(candidate)
						completions_word2i.add(candidate)
			else:
				for candidate in candidates:
					if candidate not in completions_word2i:
						completions_i2word.append(candidate)
						completions_word2i.add(candidate)

	vim.command("call add(completions_i2word, '')")
	for word in completions_i2word:
		vim.command("call add(completions_i2word, '" + word[len(seed):] + "')")

except: pass
EOF

	return completions_i2word
endfunction

" generate completion list
function! s:GenerateCompletions(seed, backward)
	let completions_i2word = [""]
	let completions_word2i = {}

	let regexp = '\<' . a:seed . '\w\+'
	if empty(a:seed)
		let regexp = '\<\w\w\+'
	elseif a:seed =~ '\W'
		let regexp = '\<\(\V' . escape(a:seed, '\') . '\)\w\+'
	endif

	let cursor = getpos(".")
	let wrapped = 0

	" backup 'ignorecase', do searching with 'noignorecase'
	let save_ignorecase = &ignorecase
	set noignorecase

	let r = range(cursor[1], line("$")) + range(1, cursor[1])
	if a:backward
		let r = range(cursor[1], 1, -1) + range(line("$"), cursor[1], -1)
	endif
	for l in r
		let candidates = []

		let line = getline(l)
		let start = match(line, regexp)
		while start != -1
			let candidate = matchstr(line, '\w\+', start + len(a:seed))
			let next = start + len(a:seed) + len(candidate)
			if l != cursor[1]
					\ || a:backward && (!wrapped && start < cursor[2]
						\ || wrapped && start >= cursor[2])
					\ || !a:backward && (wrapped && next < cursor[2]
						\ || !wrapped && next >= cursor[2])
				call add(candidates, candidate)
			endif
			let start = match(line, regexp, next)
		endwhile

		if l == cursor[1]
			let wrapped = 1
		endif

		if !empty(candidates)
			if a:backward
				let i = len(candidates) - 1
				while i >= 0
					if !has_key(completions_word2i, candidates[i])
						call add(completions_i2word, candidates[i])
						let completions_word2i[candidates[i]] = 1
					endif
					let i = i - 1
				endwhile
			else
				let i = 0
				while i < len(candidates)
					if !has_key(completions_word2i, candidates[i])
						call add(completions_i2word, candidates[i])
						let completions_word2i[candidates[i]] = 1
					endif
					let i = i + 1
				endwhile
			endif
		endif
	endfor

	" restore 'ignorecase'
	let &ignorecase = save_ignorecase

	return completions_i2word
endfunction

" return next completion, to be used in c_CTRL-R =
function! s:CmdlineComplete(backward)
	" define variables if they don't exist
	call s:InitVariables()

	let cmdline = getcmdline()
	let pos = getcmdpos()

	" if cmdline, cmdpos or cursor changed since last call,
	" re-generate the completion list
	if cmdline != s:last_cmdline || pos != s:last_pos
		let s:last_cmdline = cmdline
		let s:last_pos = pos

		let s = match(strpart(cmdline, 0, pos - 1), '\w*$')
		let s:seed = strpart(cmdline, s, pos - 1 - s)
		let s:completions = []
		if has('python')
			let s:completions = s:GenerateCompletionsPython(s:seed, a:backward)
		endif
		if empty(s:completions)
			let s:completions = s:GenerateCompletions(s:seed, a:backward)
		endif
		let s:comp_i = 0
		let s:comp_max = a:backward ? 1 - len(s:completions) : len(s:completions) - 1
	endif

	let old = s:completions[s:comp_i < 0 ? -s:comp_i : s:comp_i]

	if a:backward
		let s:comp_i = s:comp_i - 1
		if s:comp_max >= 0 && s:comp_i < 0
			let s:comp_i = s:comp_max
		elseif s:comp_max <= 0 && s:comp_i < s:comp_max
			let s:comp_i = 0
		endif
	else
		let s:comp_i = s:comp_i + 1
		if s:comp_max <= 0 && s:comp_i > 0
			let s:comp_i = s:comp_max
		elseif s:comp_max >= 0 && s:comp_i > s:comp_max
			let s:comp_i = 0
		endif
	endif

	let new = s:completions[s:comp_i < 0 ? -s:comp_i : s:comp_i]

	" remember the last cmdline, cmdpos and cursor for next call
	let s:last_cmdline = strpart(s:last_cmdline, 0, s:last_pos - 1 - strlen(old))
			\ . new . strpart(s:last_cmdline, s:last_pos - 1)
	let s:last_pos = s:last_pos - len(old) + len(new)

	" feed some keys to overcome map-<silent>
	call feedkeys(" \<bs>")

	return substitute(old, ".", "\<c-h>", "g") . new
endfunction
