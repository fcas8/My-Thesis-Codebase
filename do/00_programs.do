* =============================================================================
* 00_programs.do  --  small programs shared by the do-files
*
* Run (with -do-) at the top of any do-file that needs them. Defines:
*
*   export_table using <path without extension> [, title(string)]
*       Writes the data in memory as a final table, in two files:
*         <path>.xlsx  Excel, first row = variable labels (names if no label)
*         <path>.tex   LaTeX tabular (booktabs: \toprule, \midrule, \bottomrule),
*                      to \input{} in the paper. Needs \usepackage{booktabs}.
*       Column headers are the variable labels; numbers are written with each
*       variable's display format (set -format- before calling); value labels are
*       used where a variable has them. First column left-aligned, others right.
*       title() only goes into a comment line at the top of the .tex file.
*       Final tables go to output/tables/ (see output_inventory.xlsx); anything
*       that is not a paper table goes to data/temp/.
*
*   export_panel_table using <path without extension> [, title(string)]
*       The same for tables in panels, with rows in parentheses below others (see
*       the program below for the layout the data must have).
*
*   export_transposed using <path without extension> [, panel(varname) title(string)]
*       For tables with one row per period: writes periods across, statistics down
*       (the layout of all descriptive tables), via export_panel_table.
* =============================================================================

capture program drop export_table
program define export_table
    syntax using/ [, Title(string)]

    * --- Excel ---------------------------------------------------------------
    export excel using "`using'.xlsx", firstrow(varlabels) replace

    * --- LaTeX ---------------------------------------------------------------
    unab vars : _all
    local k : word count `vars'
    local align "l"
    forvalues j = 2/`k' {
        local align "`align'r"
    }
    tempname fh
    file open `fh' using "`using'.tex", write replace text
    file write `fh' "% `title'" _n
    file write `fh' "% Written by export_table (do/00_programs.do). Do not edit by hand." _n
    file write `fh' "\begin{tabular}{`align'}" _n "\toprule" _n

    * header row: variable labels
    local line ""
    local j = 0
    foreach v of local vars {
        local ++j
        local lab : variable label `v'
        if `"`lab'"' == "" local lab "`v'"
        _tex_escape `"`lab'"'
        local cell `"`r(s)'"'
        local line = cond(`j' == 1, `"`cell'"', `"`line' & `cell'"')
    }
    file write `fh' `"`line' \\"' _n "\midrule" _n

    * body
    forvalues i = 1/`=_N' {
        local line ""
        local j = 0
        foreach v of local vars {
            local ++j
            capture confirm string variable `v'
            if !_rc {
                local cell = `v'[`i']
            }
            else {
                local val = `v'[`i']
                local vl : value label `v'
                if "`vl'" != "" & `val' < . {
                    local cell : label `vl' `val'
                }
                else if `val' >= . {
                    local cell ""
                }
                else {
                    local fmt : format `v'
                    local cell = strtrim(string(`val', "`fmt'"))
                }
            }
            _tex_escape `"`cell'"'
            local cell `"`r(s)'"'
            local line = cond(`j' == 1, `"`cell'"', `"`line' & `cell'"')
        }
        file write `fh' `"`line' \\"' _n
    }
    file write `fh' "\bottomrule" _n "\end{tabular}" _n
    file close `fh'
    display as text "table written: `using'.xlsx and .tex"
end

* LaTeX special characters in a cell: & % _ # $ (escaped with a backslash; the dollar sign as \textdollar{}, since Stata drops a backslash put before it)
capture program drop _tex_escape
program define _tex_escape, rclass
    args s
    foreach c in & % _ # {
        local s : subinstr local s "`c'" "\\`c'", all
    }
    local d = char(36)
    local s : subinstr local s "`d'" "\textdollar{}", all
    return local s `"`s'"'
end

* -----------------------------------------------------------------------------
* export_panel_table using <path without extension> [, title(string)]
*   Like export_table, for tables in panels (e.g. 04 Table 1). The data in memory must
*   have: row_type (1 panel title, 2 row with numbers, 3 row in parentheses below the
*   previous one, e.g. a % or a standard error), then the row label (string), then one
*   string variable per column, already formatted. Column headers = variable labels.
*   .xlsx: same layout, row_type dropped. .tex: tabular with booktabs; panel titles in
*   italics across the table, rows with numbers indented, rows in parentheses unlabeled,
*   a little space before each panel.
* -----------------------------------------------------------------------------
capture program drop export_panel_table
program define export_panel_table
    syntax using/ [, Title(string)]

    * --- Excel ---------------------------------------------------------------
    preserve
    drop row_type
    export excel using "`using'.xlsx", firstrow(varlabels) replace
    restore

    * --- LaTeX ---------------------------------------------------------------
    unab vars : _all
    local rt_var row_type
    local vars : list vars - rt_var
    local k : word count `vars'
    local align "l"
    forvalues j = 2/`k' {
        local align "`align'r"
    }
    tempname fh
    file open `fh' using "`using'.tex", write replace text
    file write `fh' "% `title'" _n
    file write `fh' "% Written by export_panel_table (do/00_programs.do). Do not edit by hand." _n
    file write `fh' "\begin{tabular}{`align'}" _n "\toprule" _n
    local line ""
    local j = 0
    foreach v of local vars {
        local ++j
        local lab : variable label `v'
        if `"`lab'"' == "" local lab "`v'"
        _tex_escape `"`lab'"'
        local cell `"`r(s)'"'
        local line = cond(`j' == 1, `"`cell'"', `"`line' & `cell'"')
    }
    file write `fh' `"`line' \\"' _n "\midrule" _n
    quietly count if row_type == 1
    local has_panels = r(N) > 0
    forvalues i = 1/`=_N' {
        local rt = row_type[`i']
        local first : word 1 of `vars'
        _tex_escape `"`=`first'[`i']'"'
        local lab `"`r(s)'"'
        if `rt' == 1 {
            if `i' > 1 file write `fh' "\addlinespace" _n
            file write `fh' `"\multicolumn{`k'}{l}{\textit{`lab'}} \\"' _n
            continue
        }
        local line = cond(`rt' == 2, cond(`has_panels', `"\hspace{1em}`lab'"', `"`lab'"'), "")
        local j = 0
        foreach v of local vars {
            local ++j
            if `j' == 1 continue
            _tex_escape `"`=`v'[`i']'"'
            local line `"`line' & `r(s)'"'
        }
        file write `fh' `"`line' \\"' _n
    }
    file write `fh' "\bottomrule" _n "\end{tabular}" _n
    file close `fh'
    display as text "table written: `using'.xlsx and .tex"
end

* -----------------------------------------------------------------------------
* export_transposed using <path without extension> [, panel(varname) title(string)]
*   For tables whose rows are time periods: writes them with the periods ACROSS (one
*   column each) and the statistics DOWN, the layout of all descriptive tables.
*   Data in memory: the FIRST variable names the period of each row (string, or numeric
*   with a value label); with panel(), one row per panel x period, and each panel value
*   becomes a block of rows under its title (e.g. one block per group). Every other
*   variable is a statistic: one table row, labeled with its variable label and written
*   with its display format (missing = empty cell). Columns and panels keep the order
*   in which they appear in the data. Written by export_panel_table.
* -----------------------------------------------------------------------------
capture program drop export_transposed
program define export_transposed
    syntax using/ [, Panel(varname) Title(string)]
    preserve
    unab all : _all
    local cols : word 1 of `all'
    local stats : list all - cols
    if "`panel'" != "" local stats : list stats - panel

    * column and panel order: first appearance in the data
    gen long __o = _n
    foreach x in cols panel {
        if "``x''" == "" continue
        capture confirm string variable ``x''
        if _rc {
            capture decode ``x'', gen(__s_`x')
            if _rc gen __s_`x' = strtrim(string(``x''))
        }
        else gen __s_`x' = ``x''
        bysort __s_`x' (__o): gen long __f_`x' = __o[1]
        egen __i_`x' = group(__f_`x')
    }
    if "`panel'" == "" {
        gen __i_panel = 1
        gen __s_panel = ""
    }
    sort __o
    quietly summarize __i_cols, meanonly
    local nc = r(max)
    forvalues c = 1/`nc' {
        levelsof __s_cols if __i_cols == `c', local(h) clean
        local head`c' `"`h'"'
    }
    quietly summarize __i_panel, meanonly
    local np = r(max)
    forvalues p = 1/`np' {
        levelsof __s_panel if __i_panel == `p', local(h) clean
        local ptitle`p' `"`h'"'
    }

    * each statistic as text in its own format
    local j = 0
    foreach v of local stats {
        local ++j
        local lab`j' : variable label `v'
        if `"`lab`j''"' == "" local lab`j' "`v'"
        capture confirm string variable `v'
        if !_rc gen __v`j' = `v'
        else gen __v`j' = cond(`v' < ., strtrim(string(`v', "`: format `v''")), "")
    }
    local ns = `j'
    keep __i_panel __i_cols __v*
    reshape long __v, i(__i_panel __i_cols) j(__stat)
    reshape wide __v, i(__i_panel __stat) j(__i_cols)
    gen strL label = ""
    forvalues j = 1/`ns' {
        replace label = `"`lab`j''"' if __stat == `j'
    }
    gen byte row_type = 2
    if "`panel'" != "" {
        local N0 = _N
        set obs `=_N + `np''
        forvalues p = 1/`np' {
            replace __i_panel = `p' in `=`N0' + `p''
            replace __stat = 0 in `=`N0' + `p''
            replace row_type = 1 in `=`N0' + `p''
            replace label = `"`ptitle`p''"' in `=`N0' + `p''
        }
    }
    sort __i_panel __stat
    keep row_type label __v*
    order row_type label
    label var label " "
    forvalues c = 1/`nc' {
        rename __v`c' c`c'
        replace c`c' = "" if row_type == 1
        label var c`c' `"`head`c''"'
    }
    export_panel_table using "`using'", title(`"`title'"')
    restore
end
