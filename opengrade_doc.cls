\NeedsTeXFormat{LaTeX2e}
\ProvidesClass{doc}

\LoadClass[10pt]{article}


\RequirePackage{times,fancyhdr,titlesec,moreverb,lmmath}
\RequirePackage[leqno]{amsmath}

\newcommand{\hwcheckmark}{\scriptsize\raisebox{1mm}{$\surd$}\normalsize}

%========================= Helvetica for sans serif =========================
\renewcommand{\sfdefault}{phv} 

\newcommand{\mytitle}[1]{\noindent\huge{\bfseries{\sffamily{#1}}}\normalfont\normalsize}

%========================= design =========================
\newlength{\mysidemargin}
\setlength{\mysidemargin}{40mm}
% titlesec stuff:
\titleformat{\subsection}[margin]
  {\normalfont\normalsize\sffamily\filleft}{\thesection}{1em}{}
\titlespacing*{\subsection}{\mysidemargin}{0mm}{4mm}
%\titleformat{\subsection}[runin]
%  {\normalfont\normalsize\bfseries}{\thesubsection}{0mm}{}[---]
%\titlespacing{\subsection}{0mm}{1mm}{-0.5mm}
\newcommand{\mysection}[1]{\section{#1}}
\newcommand{\mysubsection}[1]{\subsection*{#1}}
\newcommand{\mysubsubsection}[1]{\normalsize\normalfont\textit{#1}\normalfont\normalsize\\*}

\newcommand{\formatlikesection}[1]{\Large{\textbf{#1}}\normalsize\normalfont}

%-------------------- page layout dimensions -------------------
% standard stuff, see LaTeX companion, p. 85:
  \setlength{\hoffset}{0mm}
  \setlength{\textwidth}{113mm}
  \setlength{\marginparsep}{0mm}
  \setlength{\marginparwidth}{0mm}
  \setlength{\columnsep}{6mm}
  \setlength{\voffset}{-4mm}
  \setlength{\textheight}{230mm}
  \setlength{\topmargin}{-12mm}
  \setlength{\headheight}{4mm}
  \setlength{\headsep}{8mm}
  \setlength{\footskip}{15mm}
  \setlength{\oddsidemargin}{\mysidemargin}
  \addtolength{\oddsidemargin}{4mm}
%--------------------to allow changing from one layout to another ------
\newlength{\normaltextwidth}
\setlength{\normaltextwidth}{\textwidth}
\newlength{\normalesm}
\setlength{\normalesm}{\evensidemargin}
\newcommand{\normallayout}{
	\clearpage
	\setlength{\textwidth}{\normaltextwidth}
	\setlength{\evensidemargin}{\normalesm}
}
\newcommand{\nomarginlayout}{
	\normallayout
	\addtolength{\textwidth}{\mysidemargin}
	\addtolength{\oddsidemargin}{-\mysidemargin}
}

%-------------------- paragraph formatting -------------------
%Have to do the following /after/ the toc:
\newcommand{\parafmt}{
	\setlength{\parindent}{0mm}
	\setlength{\parskip}{2mm}
}

%-------------------- fancyhdr -------------------
\pagestyle{fancy}
\lhead[]{}
\chead[]{}
\rhead[]{}
\lfoot[\textbf{\textsf{\thepage}}]{}
\cfoot[]{}
\rfoot[]{\textbf{\textsf{\thepage}}}
\fancypagestyle{plain}{%
  \fancyfoot{} %
}
\renewcommand{\headrulewidth}{0pt}

%------------ figures ------------------
\newcommand{\fig}[1]{\includegraphics[width=\textwidth]{#1}\label{#1}}

%========================= graphicx package=========================
\usepackage{graphicx}
%========================= AtBeginDocument stuff=========================
\AtBeginDocument{
  %------------------------------- pdf stuff
	\ifpdf
	\DeclareGraphicsExtensions{.pdf,.png}
	\else
	\DeclareGraphicsExtensions{.eps,.png}
	\fi
  %------------------------------- equation spacing 
}
