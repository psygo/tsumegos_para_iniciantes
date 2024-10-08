#!/bin/bash
# Build a PDF paperback book cover from LaTeX sources.
# ----------------------------------------------------------------------------
# LaTeX eBook utility tools
# -----------------------------------------------------------------------------
# John Fogarty - https://github.com/jfogarty - johnhenryfogarty@gmail.com
# -----------------------------------------------------------------------------

declare fullScriptName=$_
declare scriptName=$(basename $0)

# Scripts calls other scripts in the same directory by simple name.
declare absScriptFile=$(readlink -f "$0")
declare absScriptPath=$(dirname "$absScriptFile")
PATH=$absScriptPath:$PATH

declare toDir="cover"
declare parametersName

declare trialRun=0
declare verbose=0
declare quiet=0
declare logindex=1
declare showInfo=0
declare hardcover=0
declare isbn13
declare price
declare priceCode
declare hisbn13
declare hprice
declare hpriceCode
declare coverType=""
declare rv

#------------------------------------------------------------------------
# Terminate the script with a failure message.

# echo text if not quiet
function qecho()
{
    if [[ $quiet -eq 0 ]]; then
        echo "$@"
    fi
}

# echo text if in verbose mode.
function vecho()
{
    if [[ $verbose -eq 1 ]]; then
        echo "$@"
    fi
}

function fail()
{
    local msg=$1
    qecho "[$scriptName] *** Failed: $msg"
    exit 666
}

function requireFile()
{
	local fileType=$1
	local fileName=$2
    if [[ ! -e "$fileName" ]]; then
        fail "$fileType input file '$fileName' does not exist"
    fi
}

function checkDir()
{
	local dirName=$1
	local fileName=$2
    if [[ -e "$dirName" ]]; then
        local toFile="$dirName/$fileName"
        if ! [[ -e "$toFile" ]]; then
            qecho "*** Suspicious target directory. Clear it yourself first."
            fail "$toFile should exist."
        fi
    fi
}

#------------------------------------------------------------------------
# Run a command and exit if any error code is returned.
function runIgnore()
{
    if [[ $trialRun -ne 0 ]]; then
        qecho "--Run:[$@]"
    else
       vecho "- $@"
       eval "$@"
    fi
}

#------------------------------------------------------------------------
# Run a command and exit if any error code is returned.
function run()
{
    runIgnore "$@"
    local status=$?
    if [[ $status -ne 0 ]]; then
        qecho "[$scriptName] *** Error with [$1]" >&2
        exit $status
    fi
    return $status
}

#------------------------------------------------------------------------
# Remove a specified extension from a filename if its present.
# Return resulting file in rv.
function removeExtension()
{
    local fileName=$1
    local extName=$2
    if [[ "${fileName%.*}.$extName" == "$fileName" ]]; then
        fileName=${fileName%.*}
    fi
    if [[ "${fileName:(-1)}" == "." ]]; then
        fileName=${fileName%.*}
    fi    
    rv="$fileName"
}

#------------------------------------------------------------------------
# Strip : and = from argument text
function dirArg()
{
    local dirName=$1
    if [[ ${dirName:0:1} == ":" ]] ; then
        dirName=${dirName:1}
    fi
    if [[ "${dirName:0:1}" == "=" ]] ; then
        dirName=${dirName:1}
    fi
    rv="$dirName"
}

#------------------------------------------------------------------------
# Copy files to the target directory conversion (after clearing it)
function copyIfExists()
{
    local theFile=$1
    local theDest=$2
    if [[ -e "$theFile" ]]; then
        run cp "$theFile" "$theDest"
    fi
}

#------------------------------------------------------------------------
# Delete a file if it exists
function delIfExists()
{
    local theFile=$1
    if [[ -e "$theFile" ]]; then
        run rm "$theFile"
    fi
}

#------------------------------------------------------------------------
# Set up the working directory
function prepareDir()
{
    run mkdir -p "$toDir/logs"
    run cd "cover"
}

#------------------------------------------------------------------------
function evalrv()
{
    #rv=`$cmd`  # Odd perl issues. Output to tmp file instead.
    if [[ $trialRun != 0 ]]; then
        echo "--EvalRV:[$@]"
        rv=""
    else        
        eval $1 > x.tmp 
        rv=`cat x.tmp`
        rm x.tmp
    fi
}

function getBookParam()
{
    local pname=$1
    local cmd='perl -0ne '"'"'print "$2\n" if /[^%]\s*\\(def|pgfmathsetmacro)\\'"$pname"'{(.*)}/'
    local cmd+="' < ../$parametersName.tex"
    evalrv "$cmd"
}

#------------------------------------------------------------------------
# This shows the book statistics AND obtains the parameters for
# generating the ISBN barcode. Yes, its a kludge, but I'm feeling lazy
# today. Feel free to fix it.
function showStats()
{
    getBookParam "TotalPageCount"; local pages="$rv"
    getBookParam "PaperWidthPt";   local width="$rv"
    getBookParam "PaperHeightPt";  local height="$rv"

    printf '%s Book Format %s x %s (%s pages)\n' '-' $width $height $pages
    
    getBookParam "PrintISBN";       isbn13="$rv"
    if [[ -z "$isbn13" ]]; then
        printf '%s ISBN not supplied. No EAN barcode will be generated.\n' '-'
        hardcover=0
    else
        getBookParam "PrintPrice";      price="$rv"
        getBookParam "HardcoverISBN";   hisbn13="$rv"
        pb=""    
        if [[ -n "$hisbn13" ]]; then
            pb="Paperback "
            getBookParam "HardcoverPrice";  hprice="$rv"
        else
            if [[ $hardcover != 0 ]]; then 
              printf '%s Hardcover ISBN not supplied. Reverting to PrintISBN.\n' '*'
              hardcover=0
            fi
        fi
        if [[ -z "$price" ]]; then
            printf '%s %sISBN13: %s, No price supplied.\n' '-' "$pb" "$isbn13"
        else
            priceCode=0000"${price//.}"
            priceCode=5"${priceCode:(-4)}"
            printf '%s %sISBN13: %s, Price: $%s [%s]\n' '-' "$pb" "$isbn13" "$price" "$priceCode"
        fi
        if [[ -n "$hisbn13" ]]; then
            if [[ -z "$hprice" ]]; then
                printf '%s Hardcover ISBN13: %s, No hardcover price supplied.\n' '-' "$hisbn13"
            else
                hpriceCode=0000"${hprice//.}"
                hpriceCode=5"${hpriceCode:(-4)}"
                printf '%s Hardcover ISBN13: %s, Price: $%s [%s]\n' '-' "$hisbn13" "$hprice" "$hpriceCode"
            fi
        fi
    fi
}

#------------------------------------------------------------------------
# Run a command log its output to a subdirectoried log file.
function logrun()
{
    local msg=$1
    local cmd=$2
    local parms=$3
    local fromstream=$4
    local ignoreError=0
    local logbase=$(basename $cmd)
    local logfile="./logs/${logindex}_$logbase.log"
    if [[ $fromstream -lt 0 ]]; then
        let fromstream=-$fromstream
        let ignoreError=1
    fi
    if [[ $fromstream -eq 0 ]]; then
      local fullcmd="$cmd $parms | tee $logfile"
    else 
      local fullcmd="$cmd $parms $fromstream> $logfile"
    fi
    qecho "- $msg"
    if [[ $ignoreError -eq 0 ]]; then
        run "$fullcmd" 
    else
        runIgnore "$fullcmd" 
    fi
    let logindex+=1
}

#------------------------------------------------------------------------
# Make an ISBN barcode with price
function makeBarcode()
{
    local isbnFile="ISBN.ps"
    local isbnImage="ISBN.png"
    local gsParms="-dSAFER -dBATCH -dNOPAUSE -sDEVICE=pnggray -dTextAlphaBits=4 -r600"
    local imageParm="-g1480x800"
    if [[ -n "$isbn13" ]]; then
        coverType=" (paperback)"
        if [[ $hardcover -ne 0 ]]; then
            coverType=" (hardcover)"
            isbn13="$hisbn13"
            priceCode="$hpriceCode"
        fi 
        run "cat ../bin/external/barcode.ps > $isbnFile"
        if [[ -z "$priceCode" ]]; then
            imageParm="-g1070x800"            
            run "echo '15 10 moveto ($isbn13) (includetext) /isbn /uk.co.terryburton.bwipp findresource exec' >> $isbnFile"
        else
            run "echo '15 10 moveto ($isbn13 $priceCode) (includetext) /isbn /uk.co.terryburton.bwipp findresource exec' >> $isbnFile"
        fi
        run "echo '0 -17 rmoveto (ISBN) show' >> $isbnFile"
        run "echo 'showpage' >> $isbnFile"
        logrun "GhostScript generation of ISBN Barcode image" "gs" "$gsParms $imageParm -sOutputFile=$isbnImage $isbnFile" 1
    else
        delIfExists "$isbnFile"
        delIfExists "$isbnImage"
    fi
}
 
#------------------------------------------------------------------------
# Make the book cover using LaTeX
function makeCover()
{
    local pdfparms="-synctex=1 -interaction=nonstopmode "
    local tex="lualatex"
    logrun "Pass 1 - Generating Front Cover"           $tex "$pdfparms FrontCover.tex" 1
    logrun "Pass 1 - Generating Back Cover$coverType"  $tex "$pdfparms BackCover.tex" 1
    logrun "Pass 1 - Generating Spine for Cover"       $tex "$pdfparms SpineCover.tex" 1
    logrun "Pass 2 - Generating Front Cover"           $tex "$pdfparms FrontCover.tex" 1
    logrun "Pass 2 - Generating Back Cover$coverType"  $tex "$pdfparms BackCover.tex" 1
    logrun "Pass 2 - Generating Spine for Cover"       $tex "$pdfparms SpineCover.tex" 1
    logrun "Assembling Final Cover$coverType"          $tex "$pdfparms Cover.tex" 1
    logrun "Removing intermediate files"               "../bin/texclean.sh" "-a" 1
    run "cp Cover.pdf .."
}

#------------------------------------------------------------------------
function scriptUsage()
{
    echo "Usage: $scriptName [options]"
    echo "Build a LaTeX Print on Demand Paperback PDF cover"
    echo ""
    echo "Options:"
    echo "  -g   Use hardCover ISBN and optional price for barcode."
    echo "  -t   trial run -- commands are shown but not executed."
    echo "  -v   verbose output during command execution."
    echo "  -q   quiet output during command execution."
    echo "  -i   show information about book cover."
    echo ""
    echo "The spine width of the cover depends on the TotalPageCount defined"
    echo "in BookParameters.tex. There are two ways to set this:"
    echo "  [1] manually edit BookParameters.tex, or"
    echo "  [2] set with the command 'setBookParameter TotalPageCount'"
    exit 1
}

#------------------------------------------------------------------------
function main()
{
    logindex=1 #Start the log numbering over each run.
    parametersName="BookParameters"
    requireFile "BookParameters"  "$parametersName.tex"
    requireFile "Cover" "cover/Cover.tex"
    if [[ $showInfo -eq 1 ]]; then
        run cd "cover"
        showStats
    else 
        prepareDir
        showStats
        makeBarcode
        makeCover
        qecho "- Done."
    fi    
    exit 0
}

OPTIND=1 # Reset in case getopts has been used previously in the shell.
while getopts "h?gvqti" opt; do
    case "$opt" in
        h|\?)
            scriptUsage
            exit 0
            ;;
        g)  hardcover=1
            ;;            
        i)  showInfo=1
            ;;            
        v)  verbose=1
            ;;
        q)  quiet=1
            ;;
        t)  trialRun=1
            ;;
    esac
done
shift $((OPTIND-1))
[ "$1" = "--" ] && shift
main "$1" "$2"
# - End of bash script.

