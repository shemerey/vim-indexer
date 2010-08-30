"=============================================================================
" File:        indexer.vim
" Author:      Dmitry Frank (dimon.frank@gmail.com)
" Last Change: Wed 25 Aug 2010
" Version:     1.2
"=============================================================================
" See documentation in accompanying help file
" You may use this code in whatever way you see fit.


" s:ParsePath(sPath)
"   changing '\' to '/' or vice versa depending on OS (MS Windows or not) also calls simplify()
function! s:ParsePath(sPath)
   if (has('win32') || has('win64'))
      let l:sPath = substitute(a:sPath, '/', '\', 'g')
   else
      let l:sPath = substitute(a:sPath, '\', '/', 'g')
   endif
   let l:sPath = simplify(l:sPath)
   return l:sPath
endfunction


" s:Trim(sString)
" trims spaces from begin and end of string
function! s:Trim(sString)
   return substitute(substitute(a:sString, '^\s\+', '', ''), '\s\+$', '', '')
endfunction
   
" s:IsAbsolutePath(path) <<<
"   this function from project.vim is written by Aric Blumer. 
"   Returns true if filename has an absolute path.
function! s:IsAbsolutePath(path)
   if a:path =~ '^ftp:' || a:path =~ '^rcp:' || a:path =~ '^scp:' || a:path =~ '^http:'
      return 2
   endif
   if a:path =~ '\$'
      let path=expand(a:path) " Expand any environment variables that might be in the path
   else
      let path=a:path
   endif
   if path[0] == '/' || path[0] == '~' || path[0] == '\\' || path[1] == ':'
      return 1
   endif
   return 0
endfunction " >>>

" getting dictionary with files, paths and non-existing files from indexer
" project file
function! s:GetDirsAndFilesFromIndexerFile(indexerFile, projectName)
   let l:aLines = readfile(a:indexerFile)
   let l:boolInNeededProject = (a:projectName == '' ? 1 : 0)

   let l:sCurProjName = ''
   let l:dResult = {}

   for l:sLine in l:aLines
      
      
   
      " if line is not empty
      if l:sLine !~ '^\s*$' && l:sLine !~ '^\s*\#.*$'

         " look for project name [PrjName]
         let myMatch = matchlist(l:sLine, '^\s*\[\([^\]]\+\)\]') 

         if (len(myMatch) > 0)
            
            if (a:projectName != '')
               if (myMatch[1] == a:projectName)
                  let l:boolInNeededProject = 1
               else
                  let l:boolInNeededProject = 0
               endif
            endif

            if l:boolInNeededProject
               let l:sCurProjName = myMatch[1]
               let l:dResult[l:sCurProjName] = { 'files': [], 'paths': [], 'not_exist': [] }
            endif
         else

            if l:boolInNeededProject
               " looks like there's path
               if l:sCurProjName == ''
                  let l:sCurProjName = 'noname'
                  let l:dResult[l:sCurProjName] = { 'files': [], 'paths': [], 'not_exist': [] }
               endif
               let l:dResult[l:sCurProjName].files = <SID>ConcatLists(l:dResult[l:sCurProjName].files, split(expand(substitute(<SID>Trim(l:sLine), '\\\*\*', '**', 'g')), '\n'))
            endif
         endif
      endif



   endfor

   " build paths
   for l:sKey in keys(l:dResult)
      let l:lPaths = []
      for l:sFile in l:dResult[l:sKey].files
         let l:sPath = substitute(l:sFile, '^\(.*\)[\\/][^\\/]\+$', '\1', 'g')
         call add(l:lPaths, l:sPath)
      endfor

      let l:dResult[l:sKey].paths = <SID>ConcatLists(l:dResult[l:sKey].paths, l:lPaths)

   endfor

   return l:dResult
endfunction

" getting dictionary with files, paths and non-existing files from
" project.vim's project file
function! s:GetDirsAndFilesFromProjectFile(projectFile, projectName)
   let l:aLines = readfile(a:projectFile)
   " if projectName is empty, then we should add files from whole projectFile
   let l:boolInNeededProject = (a:projectName == '' ? 1 : 0)

   let l:iOpenedBraces = 0 " current count of opened { }
   let l:iOpenedBracesAtProjectStart = 0
   let l:aPaths = [] " paths stack
   let l:sLastFoundPath = ''

   let l:dResult = {}
   let l:sCurProjName = ''

   for l:sLine in l:aLines
      " searching for closing brace { }
      let sTmpLine = l:sLine
      while (sTmpLine =~ '}')
         let l:iOpenedBraces = l:iOpenedBraces - 1

         " if projectName is defined and there was last brace closed, then we
         " are finished parsing needed project
         if (l:iOpenedBraces <= l:iOpenedBracesAtProjectStart) && a:projectName != ''
            let l:boolInNeededProject = 0
            " TODO: total break
         endif
         call remove(l:aPaths, len(l:aPaths) - 1)

         let sTmpLine = substitute(sTmpLine, '}', '', '')
      endwhile

      " searching for blabla=qweqwe 
      let myMatch = matchlist(l:sLine, '\s*\(.\{-}\)=\(.\{-}\)\\\@<!\(\s\|$\)')
      if (len(myMatch) > 0)
         " now we found start of project folder or subfolder
         "
         if !l:boolInNeededProject
            if (a:projectName != '' && myMatch[1] == a:projectName)
               let l:iOpenedBracesAtProjectStart = l:iOpenedBraces
               let l:boolInNeededProject = 1
            endif
         endif

         if l:boolInNeededProject && (l:iOpenedBraces == l:iOpenedBracesAtProjectStart)
            let l:sCurProjName = myMatch[1]
            let l:dResult[myMatch[1]] = { 'files': [], 'paths': [], 'not_exist': [] }
         endif

         let l:sLastFoundPath = myMatch[2]
         if l:sLastFoundPath =~ '\$'
            let l:sLastFoundPath=expand(l:sLastFoundPath) " Expand any environment variables that might be in the path
         endif
         let l:sLastFoundPath = s:ParsePath(l:sLastFoundPath)

      endif

      " searching for opening brace { }
      let sTmpLine = l:sLine
      while (sTmpLine =~ '{')

         if (s:IsAbsolutePath(l:sLastFoundPath) || len(l:aPaths) == 0)
            call add(l:aPaths, s:ParsePath(l:sLastFoundPath))
         else
            call add(l:aPaths, s:ParsePath(l:aPaths[len(l:aPaths) - 1].'/'.l:sLastFoundPath))
         endif

         let l:iOpenedBraces = l:iOpenedBraces + 1

         if (l:boolInNeededProject && l:iOpenedBraces > l:iOpenedBracesAtProjectStart && isdirectory(l:aPaths[len(l:aPaths) - 1]))
            call add(l:dResult[l:sCurProjName].paths, l:aPaths[len(l:aPaths) - 1])
         endif

         let sTmpLine = substitute(sTmpLine, '{', '', '')
      endwhile

      " searching for filename
      if (l:sLine =~ '^[^={}]*$')
         " here we are found something like filename
         "
         if (l:boolInNeededProject && l:iOpenedBraces > l:iOpenedBracesAtProjectStart)
            " we are in needed project
            let l:sCurFilename = s:ParsePath(l:aPaths[len(l:aPaths) - 1].'/'.s:Trim(l:sLine))
            if (filereadable(l:sCurFilename))
               " file readable! adding it
               call add(l:dResult[l:sCurProjName].files, l:sCurFilename)
            else
               call add(l:dResult[l:sCurProjName].not_exist, l:sCurFilename)
            endif
         endif

      endif

      "
      "
   endfor

   return l:dResult
endfunction


" returns whether or not file exists in list
function! s:IsFileExistsInList(aList, sFilename)
   let l:sFilename = s:ParsePath(a:sFilename)
   if (index(a:aList, l:sFilename, 0, 1)) >= 0
      return 1
   endif
   return 0
endfunction

" updating tags using ctags. 
" if boolAppend then just appends existing tags file with new tags from
" current file (%)
function! s:UpdateTags(boolAppend)
   " multiple files, call from Vim
   "for l:sFile in s:lFileList
      "let l:cmd = 'ctags -f '.s:tagsDirname.'/'.substitute(l:sFile, '[\\/:]', '%', 'g').' '.g:indexer_ctagsCommandLineOptions.' '.l:sFile
      "let l:resp = system(l:cmd)
   "endfor

   " one tags file
   let l:sTagsFile = s:tagsDirname.'/tags'
   if !isdirectory(s:tagsDirname)
      call mkdir(s:tagsDirname, "p")
   endif

   if (a:boolAppend && filereadable(l:sTagsFile))
      let l:sAppendCode = '-a'
      let l:sFile = <SID>ParsePath(expand('%:p'))
      if (<SID>IsFileExistsInList(s:lFileList, l:sFile))
         " saved file are in file list
         let l:sFiles = l:sFile
      elseif (<SID>IsFileExistsInList(s:lNotExistFiles, l:sFile))
         let l:sFiles = l:sFile

         " moving file from non-existing list to existing list
         call remove(s:lNotExistFiles, index(s:lNotExistFiles, l:sFile))
         call add(s:lFileList, l:sFile)
      else
         let l:sFiles = ''
      endif

   else
      let l:sAppendCode = ''
      let l:sFiles = ''
      for l:sFile in s:lFileList
         let l:sFiles = l:sFiles.' '.l:sFile
      endfor
   endif

   if l:sFiles != ''
      if (has('win32') || has('win64'))
         let l:sTagsFile = '"'.l:sTagsFile.'"'
      endif
      " here i tried to remove all lines with current filename in tags file
      "if (l:sAppendCode != '')
         "let l:cmd = 'sed -i -e "/'.substitute(substitute(expand('%:p'), "\\([\\\\]\\)", '\\\\\\\\', 'g'), "\\([.:]\\)", '\\\1', 'g').'/d" '.l:sTagsFile
         "call system(l:cmd)
      "endif

      if (has('win32') || has('win64'))
         let l:cmd = 'ctags -f '.l:sTagsFile.' '.l:sAppendCode.' '.g:indexer_ctagsCommandLineOptions.' '.l:sFiles
      else
         let l:cmd = 'ctags -f '.l:sTagsFile.' '.l:sAppendCode.' '.g:indexer_ctagsCommandLineOptions.' '.l:sFiles.' &'
      endif
      let l:resp = system(l:cmd)
      exec 'set tags='.substitute(s:tagsDirname, ' ', '\\\\\\ ', 'g').'/tags'
   endif

   "multiple files, calls from bat file
   "exec 'set tags='
   "let l:lLines = []
   "for l:sFile in s:lFileList
      "let l:sTagFile = s:tagsDirname.'/'.substitute(l:sFile, '[\\/:]', '_', 'g')
      "call add(l:lLines, 'ctags -f '.l:sTagFile.' '.g:indexer_ctagsCommandLineOptions.' '.l:sFile)
      "exec 'set tags+='.l:sTagFile
   "endfor
   "call writefile(l:lLines, s:tagsDirname.'/maketags.bat')

   "let l:cmd = s:tagsDirname.'/maketags.bat'
   "let l:resp = system(l:cmd)
endfunction

function! s:ApplyProjectSettings(dParse)
   " paths for Vim
   set path=.
   for l:sPath in a:dParse.paths
      if isdirectory(l:sPath)
         exec 'set path+='.l:sPath
      endif
   endfor

   let s:lFileList = a:dParse.files
   let s:lNotExistFiles = a:dParse.not_exist

   augroup Indexer_SavSrcFile
   autocmd! Indexer_SavSrcFile BufWritePost
   " collect extensions of files in project to make autocmd on save these
   " files
   let l:sExtsList = ''
   let l:lFullList = s:lFileList + s:lNotExistFiles
   for l:lFile in l:lFullList
      let l:sExt = substitute(l:lFile, '^.*\([.\\/][^.\\/]\+\)$', '\1', '')
      if strpart(l:sExt, 0, 1) != '.'
         let l:sExt = strpart(l:sExt, 1)
      endif
      if (stridx(l:sExtsList, l:sExt) == -1)
         if (l:sExtsList != '')
            let l:sExtsList = l:sExtsList.','
         endif
         let l:sExtsList = l:sExtsList.'*'.l:sExt
      endif
   endfor

   " defining autocmd at source files save
   exec 'autocmd Indexer_SavSrcFile BufWritePost '.l:sExtsList.' call <SID>UpdateTags('.(g:indexer_ctagsJustAppendTagsAtFileSave ? '1' : '0').')'

   " start full tags update
   call <SID>UpdateTags(0)
endfunction

" concatenates two lists preventing duplicates
function! s:ConcatLists(lExistingList, lAddingList)
   let l:lResList = a:lExistingList
   for l:sItem in a:lAddingList
      if (index(l:lResList, l:sItem) == -1)
         call add(l:lResList, l:sItem)
      endif
   endfor
   return l:lResList
endfunction

function! s:ParseProjectSettingsFile()
   if (filereadable(g:indexer_indexerListFilename))
      " read all projects from proj file
      let s:sMode = 'IndexerFile'
      let s:dParseAll = s:GetDirsAndFilesFromIndexerFile(g:indexer_indexerListFilename, g:indexer_projectName)
   elseif (filereadable(g:indexer_projectsSettingsFilename))
      let s:sMode = 'ProjectFile'
      let s:dParseAll = s:GetDirsAndFilesFromProjectFile(g:indexer_projectsSettingsFilename, g:indexer_projectName)
   else
      let s:sMode = ''
      let s:dParseAll = {}
   endif

   " let's found what files we should to index.
   "     

   let s:iTotalFilesAvailableCnt = 0
   if (!s:boolIndexingModeOn)
      for l:sKey in keys(s:dParseAll)
         let s:iTotalFilesAvailableCnt = s:iTotalFilesAvailableCnt + len(s:dParseAll[l:sKey].files)

         if ((g:indexer_enableWhenProjectDirFound && <SID>IsFileExistsInList(s:dParseAll[l:sKey].paths, expand('%:p:h'))) || (<SID>IsFileExistsInList(s:dParseAll[l:sKey].files, expand('%:p'))))
            " user just opened file from project l:sKey. We should add it to
            " result lists
            
            " adding name of this project to g:indexer_indexedProjects
            call add(g:indexer_indexedProjects, l:sKey)

         endif
      endfor
   endif

   " build final list of files, paths and non-existing files
   let l:dParse = { 'files':[], 'paths':[], 'not_exist':[] }
   for l:sKey in g:indexer_indexedProjects
      let l:dParse.files = <SID>ConcatLists(l:dParse.files, s:dParseAll[l:sKey].files)
      let l:dParse.paths = <SID>ConcatLists(l:dParse.paths, s:dParseAll[l:sKey].paths)
      let l:dParse.not_exist = <SID>ConcatLists(l:dParse.not_exist, s:dParseAll[l:sKey].not_exist)
   endfor

   if (s:boolIndexingModeOn)
      call <SID>ApplyProjectSettings(l:dParse)
   else
      if (len(l:dParse.files) > 0 || len(l:dParse.paths) > 0)

         let s:boolIndexingModeOn = 1
         
         " creating auto-refresh index at project file save
         augroup Indexer_SavPrjFile
         autocmd! Indexer_SavPrjFile BufWritePost

         if (filereadable(g:indexer_indexerListFilename))
            let l:sIdxFile = substitute(g:indexer_indexerListFilename, '^.*[\\/]\([^\\/]\+\)$', '\1', '')
            exec 'autocmd Indexer_SavPrjFile BufWritePost '.l:sIdxFile.' call <SID>ParseProjectSettingsFile()'
         elseif (filereadable(g:indexer_projectsSettingsFilename))
            let l:sPrjFile = substitute(g:indexer_projectsSettingsFilename, '^.*[\\/]\([^\\/]\+\)$', '\1', '')
            exec 'autocmd Indexer_SavPrjFile BufWritePost '.l:sPrjFile.' call <SID>ParseProjectSettingsFile()'
         endif
         





         call <SID>ApplyProjectSettings(l:dParse)
         
         let l:iNonExistingCnt = len(s:lNotExistFiles)
         if (l:iNonExistingCnt > 0)
            if l:iNonExistingCnt < 100
               echo "Indexer Warning: project loaded, but there's ".l:iNonExistingCnt." non-existing files: \n\n".join(s:lNotExistFiles, "\n")
            else
               echo "Indexer Warning: project loaded, but there's ".l:iNonExistingCnt." non-existing files. Type :IndexerInfo for details."
            endif
         endif
         "TODO: warnings, started
      else
         " there's no project started.
         " we should define autocmd to detect if file from project will be opened later
         augroup Indexer_LoadFile
         autocmd! Indexer_LoadFile BufReadPost
         autocmd Indexer_LoadFile BufReadPost * call <SID>IndexerInit()
      endif
   endif
endfunction

function! s:IndexerFilesAvailList()
   for l:sProject in keys(s:dParseAll)
      echo 'Project name: '.l:sProject."\n\n"
      for l:sFile in s:dParseAll[l:sProject].files
         echo l:sFile
      endfor
      echo "\n---------------------------------------\n"
   endfor
endfunction

function! s:IndexerInfo()
   if (s:sMode == '')
      echo '* Filelist: not found'
   elseif (s:sMode == 'IndexerFile')
      echo '* Filelist: indexer file: '.g:indexer_indexerListFilename.' (total files: '.s:iTotalFilesAvailableCnt.'. Type :IndexerFilesAvail for details)'
   elseif (s:sMode == 'ProjectFile')
      echo '* Filelist: project file: '.g:indexer_projectsSettingsFilename.' (total files: '.s:iTotalFilesAvailableCnt.'. Type :IndexerFilesAvail for details)'
   else
      echo '* Filelist: Unknown'
   endif
   echo '* Projects indexed: '.join(g:indexer_indexedProjects, ', ')
   echo "* Files indexed: there's ".len(s:lFileList).' files. Type :IndexerFiles to list'
   echo "* Files not found: there's ".len(s:lNotExistFiles).' non-existing files. '.join(s:lNotExistFiles, ', ')
   echo '* Paths: '.&path
   echo '* Tags file: '.&tags
   echo '* Project root: '.($INDEXER_PROJECT_ROOT != '' ? $INDEXER_PROJECT_ROOT : 'not found').'  (Project root is a directory which contains "'.g:indexer_dirNameForSearch.'" directory)'
endfunction

function! s:IndexerFilesList()
   echo "* Files indexed: ".join(s:lFileList, ', ')
endfunction

function! s:IndexerInit()

   augroup Indexer_LoadFile
   autocmd! Indexer_LoadFile BufReadPost

   if !exists('g:indexer_lookForProjectDir')
      let g:indexer_lookForProjectDir = 1
   endif

   if !exists('g:indexer_dirNameForSearch')
      let g:indexer_dirNameForSearch = '.vim'
   endif

   if !exists('g:indexer_recurseUpCount')
      let g:indexer_recurseUpCount = 10
   endif

   if !exists('g:indexer_indexerListFilename')
      let g:indexer_indexerListFilename = $HOME.'/.indexer_files'
   endif

   if !exists('g:indexer_projectsSettingsFilename')
      let g:indexer_projectsSettingsFilename = $HOME.'/.vimprojects'
   endif

   if !exists('g:indexer_projectName')
      let g:indexer_projectName = ''
   endif

   if !exists('g:indexer_enableWhenProjectDirFound')
      let g:indexer_enableWhenProjectDirFound = '1'
   endif

   if !exists('g:indexer_tagsDirname')
      let g:indexer_tagsDirname = $HOME.'/.vimtags'
   endif

   if !exists('g:indexer_ctagsCommandLineOptions')
      let g:indexer_ctagsCommandLineOptions = '--c++-kinds=+p+l --fields=+iaS --extra=+q'
   endif

   if !exists('g:indexer_ctagsJustAppendTagsAtFileSave')
      let g:indexer_ctagsJustAppendTagsAtFileSave = 1
   endif




   if exists(':IndexerInfo') != 2
       command -nargs=? -complete=file IndexerInfo call <SID>IndexerInfo()
   endif
   if exists(':IndexerFiles') != 2
       command -nargs=? -complete=file IndexerFiles call <SID>IndexerFilesList()
   endif
   if exists(':IndexerRebuild') != 2
       command -nargs=? -complete=file IndexerRebuild call <SID>UpdateTags(0)
   endif
   if exists(':IndexerFilesAvail') != 2
       command -nargs=? -complete=file IndexerFilesAvail call <SID>IndexerFilesAvailList()
   endif


   " actual tags dirname. If .vim directory will be found then this tags
   " dirname will be /path/to/dir/.vim/tags
   let s:tagsDirname = g:indexer_tagsDirname 
   let g:indexer_indexedProjects = []
   let s:sMode = ''
   let s:lFileList = []
   let s:lNotExistFiles = []

   let s:boolIndexingModeOn = 0

   if g:indexer_lookForProjectDir
      " need to look for .vim directory

      let l:i = 0
      let l:sCurPath = ''
      let $INDEXER_PROJECT_ROOT = ''
      while (l:i < g:indexer_recurseUpCount)
         if (isdirectory(expand('%:p:h').l:sCurPath.'/'.g:indexer_dirNameForSearch))
            let $INDEXER_PROJECT_ROOT = simplify(expand('%:p:h').l:sCurPath)
            exec 'cd '.$INDEXER_PROJECT_ROOT
            break
         endif
         let l:sCurPath = l:sCurPath.'/..'
         let l:i = l:i + 1
      endwhile

      if $INDEXER_PROJECT_ROOT != ''
         " project root was found.
         "
         " set directory for tags in .vim dir
         let s:tagsDirname = $INDEXER_PROJECT_ROOT.'/'.g:indexer_dirNameForSearch.'/tags'

         " sourcing all *vim files in .vim dir
         let l:lSourceFilesList = split(glob($INDEXER_PROJECT_ROOT.'/'.g:indexer_dirNameForSearch.'/*vim'), '\n')
         let l:sThisFile = expand('%:p')
         for l:sFile in l:lSourceFilesList
            if (l:sFile != l:sThisFile)
               exec 'source '.l:sFile
            endif
         endfor
      endif

   endif

   call s:ParseProjectSettingsFile()

endfunction


call s:IndexerInit()

