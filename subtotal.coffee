callWithJQuery = (pivotModule) ->
    if typeof exports is "object" and typeof module is "object" # CommonJS
        pivotModule require("jquery")
    else if typeof define is "function" and define.amd # AMD
        define ["jquery"], pivotModule
    # Plain browser env
    else
        pivotModule jQuery

callWithJQuery ($) ->

    class SubtotalPivotData extends $.pivotUtilities.PivotData
        constructor: (input, opts) ->
            super input, opts

        processKey = (record, totals, keys, attrs, getAggregator) ->
            key = []
            addKey = false
            for attr in attrs
                key.push record[attr] ? "null"
                flatKey = key.join String.fromCharCode(0)
                if not totals[flatKey]
                    totals[flatKey] = getAggregator key.slice()
                    addKey = true
                totals[flatKey].push record
            keys.push key if addKey
            return key

        processRecord: (record) -> #this code is called in a tight loop
            rowKey = []
            colKey = []

            @allTotal.push record
            rowKey = processKey record, @rowTotals, @rowKeys, @rowAttrs, (key) =>
                return @aggregator this, key, []
            colKey = processKey record, @colTotals, @colKeys, @colAttrs, (key) =>
                return @aggregator this, [], key
            m = rowKey.length-1
            n = colKey.length-1
            return if m < 0 or n < 0
            for i in [0..m]
                fRowKey = rowKey.slice(0, i+1)
                flatRowKey = fRowKey.join String.fromCharCode(0)
                @tree[flatRowKey] = {} if not @tree[flatRowKey]
                for j in [0..n]
                    fColKey = colKey.slice 0, j+1
                    flatColKey = fColKey.join String.fromCharCode(0)
                    @tree[flatRowKey][flatColKey] = @aggregator this, fRowKey, fColKey if not @tree[flatRowKey][flatColKey]
                    @tree[flatRowKey][flatColKey].push record

    $.pivotUtilities.SubtotalPivotData = SubtotalPivotData

    SubtotalRenderer = (pivotData, opts) ->
        defaults =
            table: clickCallback: null
            localeStrings: totals: "Totals"

        opts = $.extend true, {}, defaults, opts

        isRowDisable = opts.rowSubtotalDisplay?.disableSubtotal
        rowDisableAfter = if typeof opts.rowSubtotalDisplay?.disableAfter isnt 'undefined' then opts.rowSubtotalDisplay.disableAfter else 9999
        if typeof opts.rowSubtotalDisplay?disableFrom is 'undefined'
            rowDisableFrom = if isRowDisable then 0 else rowDisableAfter + 1
        else
            rowDisableFrom = opts.rowSubtotalDisplay.disableFrom
        isRowHideOnExpand = opts.rowSubtotalDisplay?.hideOnExpand
        isRowDisableExpandCollapse = opts.rowSubtotalDisplay?.disableExpandCollapse
        isDisplayOnTop = if typeof opts.rowSubtotalDisplay?.displayOnTop isnt 'undefined' then opts.rowSubtotalDisplay.displayOnTop else true
        isColDisable = opts.colSubtotalDisplay?.disableSubtotal
        isColHideOnExpand = opts.colSubtotalDisplay?.hideOnExpand
        isColDisableExpandCollapse = opts.colSubtotalDisplay?.disableExpandCollapse
        colDisableAfter = if typeof opts.colSubtotalDisplay?.disableAfter isnt 'undefined' then opts.colSubtotalDisplay.disableAfter else 9999
        isDisplayOnRight = if typeof opts.colSubtotalDisplay?.displayOnRight isnt 'undefined' then opts.rowSubtotalDisplay.displayOnRight else true
        arrowCollapsed = opts.arrowCollapsed ?= "\u25B6"
        arrowExpanded = opts.arrowExpanded ?= "\u25E2"
        colsCollapseAt = if typeof opts.collapseColsAt isnt 'undefined' then opts.collapseColsAt else 9999
        rowsCollapseAt = if typeof opts.collapseRowsAt isnt 'undefined' then opts.collapseRowsAt else 9999

        colAttrs = pivotData.colAttrs
        rowAttrs = pivotData.rowAttrs
        rowKeys = pivotData.getRowKeys()
        colKeys = pivotData.getColKeys()
        tree = pivotData.tree
        rowTotals = pivotData.rowTotals
        colTotals = pivotData.colTotals
        allTotal = pivotData.allTotal

        classRowExpanded = "rowexpanded"
        classRowCollapsed = "rowcollapsed"
        classRowHide = "rowhide"
        classRowShow = "rowshow"
        classColExpanded = "colexpanded"
        classColCollapsed = "colcollapsed"
        classColHide = "colhide"
        classColShow = "colshow"
        clickStatusExpanded = "expanded"
        clickStatusCollapsed = "collapsed"
        classExpanded = "expanded"
        classCollapsed = "collapsed"

        colArrowOnInit = arrowExpanded
        colClassOnInit = classColExpanded
        colClickStatusOnInit = clickStatusExpanded

        rowArrowOnInit = arrowExpanded
        rowClassOnInit = classRowExpanded
        rowClickStatusOnInit = clickStatusExpanded
 
        # Based on http://stackoverflow.com/questions/195951/change-an-elements-class-with-javascript -- Begin
        hasClass = (element, className) ->
            regExp = new RegExp "(?:^|\\s)" + className + "(?!\\S)", "g"
            element.className.match(regExp) isnt null

        removeClass = (element, className) ->
            for name in className.split " "
                regExp = new RegExp "(?:^|\\s)" + name + "(?!\\S)", "g"
                element.className = element.className.replace regExp, ''

        addClass = (element, className) ->
            for name in className.split " "
                element.className += (" " + name) if not hasClass element, name

        replaceClass = (element, replaceClassName, byClassName) ->
            removeClass element, replaceClassName
            addClass element, byClassName
        # Based on http://stackoverflow.com/questions/195951/change-an-elements-class-with-javascript -- End

        getTableEventHandlers = (value, rowValues, colValues) ->
            return if not opts.table and not opts.table.eventHandlers
            eventHandlers = {}
            for own event, handler of opts.table.eventHandlers
                filters = {}
                filters[attr] = colValues[i] for own i, attr of colAttrs when colValues[i]?
                filters[attr] = rowValues[i] for own i, attr of rowAttrs when rowValues[i]?
                eventHandlers[event] = (e) -> handler(e, value, filters, pivotData)
            return eventHandlers

        createElement = (elementType, className, textContent, attributes, eventHandlers) ->
            e = document.createElement elementType
            e.className = className if className?
            e.textContent = textContent if textContent?
            e.setAttribute attr, val for own attr, val of attributes if attributes?
            e.addEventListener event, handler for own event, handler of eventHandlers if eventHandlers?
            return e

        setAttributes = (e, attrs) ->
            for own a, v of attrs
                e.setAttribute a, v 

        processKeys = (keysArr, className) ->
            headers = []
            lastRow = keysArr.length - 1
            lastCol = keysArr[0].length - 1
            rMark = []
            th = createElement "th", className, keysArr[0][0]
            key = []
            key.push keysArr[0][0]
            nodePos = 0
            node = {
                node: nodePos,
                row: 0,
                col: 0,
                th: th,
                parent: null,
                children: [],
                descendants: lastCol,
                leaves: 1,
                key: key,
                flatKey: key.join String.fromCharCode(0)}
            headers.push node
            rMark[0] = node
            c = 1
            while c <= lastCol
                th = createElement "th", className, keysArr[0][c]
                key = key.slice()
                key.push keysArr[0][c]
                ++nodePos
                node =  {
                    node: nodePos,
                    row: 0,
                    col: c,
                    th: th,
                    parent: rMark[c-1],
                    children: [],
                    descendants: lastCol-c,
                    leaves: 1,
                    key: key,
                    flatKey: key.join String.fromCharCode(0)}
                rMark[c] = node
                rMark[c-1].children.push node
                ++c
            rMark[lastCol].leaves = 0
            r = 1
            while r <= lastRow
                repeats = true
                key = []
                c = 0
                while c <= lastCol
                    key = key.slice()
                    key.push keysArr[r][c]
                    if ((keysArr[r][c] is keysArr[rMark[c].row][c]) and (c isnt lastCol)  and (repeats))
                        repeats = true
                        ++c
                        continue
                    th = createElement "th", className, keysArr[r][c]
                    ++nodePos
                    node = {
                        node: nodePos,
                        row: r,
                        col: c,
                        th: th,
                        parent: null,
                        children: [],
                        descendants: 0,
                        leaves: 0,
                        key: key,
                        flatKey: key.join String.fromCharCode(0)}
                    if c is 0
                        headers.push node
                    else
                        node.parent = rMark[c-1]
                        rMark[c-1].children.push node
                        x = 0
                        while x <= c-1
                            ++rMark[x].descendants
                            ++x
                    rMark[c] = node
                    repeats = false
                    ++c
                ++rMark[c].leaves for c in [0..lastCol]
                rMark[lastCol].leaves = 0
                ++r
            return headers

        setColInitParams = (col) ->
            colArrowOnInit = arrowExpanded
            colClassOnInit = classColExpanded
            colClickStatusOnInit = clickStatusExpanded

            if col >= colsCollapseAt and not (isColDisable or col > colDisableAfter) 
                colArrowOnInit = arrowCollapsed
                colClassOnInit = classColCollapsed
                colClickStatusOnInit = clickStatusCollapsed

        buildColHeaderHeader = (thead, colHeaderHeaders, rowAttrs, colAttrs, tr, col) ->
            colAttr = colAttrs[col]
            textContent = colAttr
            className = "pvtAxisLabel"
            setColInitParams col
            if col < colAttrs.length-1
                className += " " + colClassOnInit
                textContent = " " + colArrowOnInit + " " + colAttr if not (isColDisableExpandCollapse or isColDisable or col > colDisableAfter)
            th = createElement "th", className, textContent
            th.setAttribute "data-colAttr", colAttr
            tr.appendChild th
            colHeaderHeaders.push {
                tr: tr,
                th: th,
                clickStatus: colClickStatusOnInit,
                expandedCount: 0,
                nHeaders: 0}
            thead.appendChild tr

        buildColHeaderHeaders = (thead, colHeaderHeaders, rowAttrs, colAttrs) ->
            tr = createElement "tr"
            if rowAttrs.length != 0
                tr.appendChild createElement "th", null, null, {
                    colspan: rowAttrs.length,
                    rowspan: colAttrs.length}
            buildColHeaderHeader thead, colHeaderHeaders, rowAttrs, colAttrs, tr, 0
            for c in [1..colAttrs.length] when c < colAttrs.length
                tr = createElement("tr")
                buildColHeaderHeader thead, colHeaderHeaders, rowAttrs, colAttrs, tr, c

        buildColHeaderHeadersClickEvents = (colHeaderHeaders, colHeaderCols, colAttrs) ->
            n = colAttrs.length-1
            for i in [0..n] when i < n
                th = colHeaderHeaders[i].th
                colAttr = colAttrs[i]
                th.onclick = (event) ->
                    event = event || window.event
                    toggleColHeaderHeader colHeaderHeaders, colHeaderCols, colAttrs, event.target.getAttribute "data-colAttr"

        buildColHeader = (colHeaderHeaders, colHeaderCols, colHeader, rowAttrs, colAttrs) ->
            # DF Recurse
            colHeader.childrenColSpan = 0
            for h in colHeader.children
                buildColHeader colHeaderHeaders, colHeaderCols, h, rowAttrs, colAttrs
            # Process
            #
            # NOTE:
            # 
            # We replace colHeader.node with colHeaderCols.length.
            # colHeader.node is not useful as columns are positioned depth-first 
            #
            setColInitParams colHeader.col
            isColSubtotal = colHeader.children.length != 0
            colHeader.node = colHeaderCols.length
            hh = colHeaderHeaders[colHeader.col]
            ++hh.expandedCount if colHeader.col <= colsCollapseAt
            ++hh.nHeaders
            tr = hh.tr
            th = colHeader.th
            addClass th, "col#{colHeader.row} colcol#{colHeader.col} #{classColShow}"
            colspan = 1
            if isColDisable or colHeader.col > colDisableAfter
                colspan = colHeader.leaves
            else if isColSubtotal and colHeader.col < colsCollapseAt
                colspan = colHeader.childrenColSpan
                colspan += 1 if not isColHideOnExpand
            if colHeader.parent
                colHeader.parent.childrenColSpan += colspan
            setAttributes th,
                "rowspan": if colHeader.col == colAttrs.length-1 and rowAttrs.length != 0 then 2 else 1
                "colspan": colspan, 
                "data-colnode": colHeader.node,
                "data-colHeader": th.textContent
            if isColSubtotal
                addClass th, colClassOnInit
                th.textContent = " #{colArrowOnInit} #{th.textContent}" if not
                    (isColDisable or colHeader.col > colDisableAfter or isColDisableExpandCollapse)
                th.onclick = (event) ->
                    event = event || window.event
                    toggleCol colHeaderHeaders, colHeaderCols, parseInt event.target.getAttribute "data-colnode"
                rowspan = colAttrs.length-(colHeader.col+1) + if rowAttrs.length != 0 then 1 else 0
                style = "pvtColLabel pvtColSubtotal #{colClassOnInit}"
                style += " col#{colHeader.row} colcol#{colHeader.col}"
                sTh = createElement "th", style, '', {"rowspan": rowspan, "data-colnode": colHeader.node}
                addClass sTh, if isColDisable or colHeader.col > colDisableAfter or (isColHideOnExpand and colHeader.col < colsCollapseAt) then " #{classColHide}" else " #{classColShow}"
                sTh.style.display = "none" if isColDisable or colHeader.col > colDisableAfter or (isColHideOnExpand and colHeader.col < colsCollapseAt) or colHeader.col > colsCollapseAt
                colHeader.children[0].tr.appendChild sTh
                colHeader.sTh = sTh
            th.style.display = "none" if colHeader.col > colsCollapseAt

            colHeader.clickStatus = colClickStatusOnInit
            tr.appendChild(th)
            colHeader.tr = tr
            colHeaderCols.push colHeader

        setRowInitParams = (col) ->
            init = 
                rowArrow: arrowExpanded
                rowClass: classRowExpanded
                rowClickStatus: clickStatusExpanded
            if col >= rowsCollapseAt
                init =
                    rowArrow: arrowCollapsed
                    rowClass: classRowCollapsed
                    rowClickStatus: clickStatusCollapsed
            if col >= rowDisableFrom
                init =
                    rowArrow: ""
            return init

        buildRowHeaderHeaders = (thead, rowHeaderHeaders, rowAttrs, colAttrs) ->
            tr = createElement "tr"
            rowHeaderHeaders.hh = []
            for own i, rowAttr of rowAttrs
                textContent = rowAttr
                className = "pvtAxisLabel"
                if i < rowAttrs.length-1
                    className += " expanded"
                    textContent = " " + arrowExpanded + " " + rowAttr if not (isRowDisableExpandCollapse or i >= rowDisableFrom)
                th = createElement "th", className, textContent
                th.setAttribute "data-rowAttr", rowAttr
                tr.appendChild th
                rowHeaderHeaders.hh.push 
                    th: th,
                    clickStatus: clickStatusExpanded,
                    expandedCount: 0,
                    nHeaders: 0
            if colAttrs.length != 0
                th = createElement "th"
                tr.appendChild th
            thead.appendChild tr
            rowHeaderHeaders.tr = tr

        buildRowHeaderHeadersClickEvents = (rowHeaderHeaders, rowHeaderRows, rowAttrs) ->
            n = rowAttrs.length-1
            for i in [0..n] when i < n
                th = rowHeaderHeaders.hh[i]
                rowAttr = rowAttrs[i]
                th.th.onclick = (event) ->
                    event = event || window.event
                    toggleRowHeaderHeader rowHeaderHeaders, rowHeaderRows, rowAttrs, event.target.getAttribute "data-rowAttr"

        buildRowTotalsHeader = (tr, rowAttrs, colAttrs) ->
            rowspan = 1
            if colAttrs.length != 0
                rowspan = colAttrs.length + (if rowAttrs.length == 0 then 0 else 1)
            th = createElement "th", "pvtTotalLabel rowTotal", opts.localeStrings.totals, {rowspan: rowspan}
            tr.appendChild th

        buildRowHeader = (tbody, rowHeaderHeaders, rowHeaderRows, rowHeader, rowAttrs, colAttrs) ->
            # DF Recurse
            rowHeader.childrenRowSpan = 0
            for h in rowHeader.children
                buildRowHeader tbody, rowHeaderHeaders, rowHeaderRows, h, rowAttrs, colAttrs
            # Process
            #
            # NOTE:
            # 
            # We replace rowHeader.node with rowHeaderCols.length.
            # rowHeader.node is not useful as columns are positioned depth-first 
            #

            init = setRowInitParams rowHeader.col
            isRowSubtotal = rowHeader.descendants != 0
            rowHeader.node = rowHeaderRows.length
            hh = rowHeaderHeaders.hh[rowHeader.col]
            ++hh.expandedCount if rowHeader.col <= rowsCollapseAt
            ++hh.nHeaders

            tr = createElement "tr", "pvtRowSubtotal row#{rowHeader.row}", "", "data-rownode": rowHeader.node 
            th = rowHeader.th
            addClass th, "row#{rowHeader.row} rowcol#{rowHeader.col} #{classRowShow}"
            rowspan = 1
            if isRowSubtotal
                if rowHeader.col >= rowDisableFrom # --> disabled
                    rowspan = rowHeader.descendants
                    rowspan += if isDisplayOnTop then 1 else 2
                else
                    if rowHeader.col < rowsCollapseAt # --> expanded
                        rowspan = rowHeader.childrenRowSpan + 1
                        rowspan += 1 if not isDisplayOnTop
                    else  # --> collapsed
                        if isDisplayOnTop
                            rowspan = 1
                        else
                            #rowspan = rowHeader.descendants - rowHeader.leaves + 1
                            rowspan = rowHeader.childrenRowSpan+2
            if rowHeader.parent
                rowHeader.parent.childrenRowSpan += rowspan

            setAttributes th,
                "rowspan": rowspan
                "colspan": if rowHeader.col == rowAttrs.length-1 and colAttrs.length != 0 then 2 else 1
                "data-rownode": rowHeader.node,
                "data-rowHeader": th.textContent
            th.style.display = "none" if rowHeader.col > rowsCollapseAt
            tr.appendChild(th)
            if isRowSubtotal
                tbody.insertBefore tr, rowHeader.children[0].tr
            else
                tbody.appendChild tr
            rowHeader.tr = tr
 
            if isRowSubtotal
                addClass th, init.rowClass
                addClass tr, init.rowClass
                th.textContent = " #{init.rowArrow} #{th.textContent}" if not
                    (rowHeader.col >= rowDisableFrom or isRowDisableExpandCollapse)
                th.onclick = (event) ->
                    event = event || window.event
                    toggleRow rowHeaderHeaders, rowHeaderRows, parseInt event.target.getAttribute "data-rownode"
                # Filler
                colspan = rowAttrs.length-(rowHeader.col+1) + if colAttrs.length != 0 then 1 else 0
                style = "pvtRowLabel pvtRowSubtotal #{init.rowClass}"
                style += " row#{rowHeader.row} rowcol#{rowHeader.col}"
                if isDisplayOnTop
                    th = createElement "th", style, '', {"colspan": colspan, "data-rownode": rowHeader.node}
                    addClass th, if rowHeader.col >= rowDisableFrom or (isRowHideOnExpand and rowHeader.col < rowsCollapseAt) then " #{classRowHide}" else " #{classRowShow}"
                    th.style.display = "none" if rowHeader.col >= rowDisableFrom or rowHeader.col > rowsCollapseAt or not isDisplayOnTop or (isRowHideOnExpand and rowHeader.col < rowsCollapseAt)
                    tr.appendChild th
                    rowHeader.sTr = tr
                else 
                    tr = createElement "tr", "pvtRowSubtotal row#{rowHeader.row}", "", "data-rownode": rowHeader.node 
                    th = createElement "th", style, '', {"colspan": colspan, "data-rownode": rowHeader.node}
                    addClass th, if rowHeader.col >= rowDisableFrom or (isRowHideOnExpand and rowHeader.col < rowsCollapseAt) then " #{classRowHide}" else " #{classRowShow}"
                    th.style.display = "none" if rowHeader.col >= rowDisableFrom or rowHeader.col > rowsCollapseAt or (isRowHideOnExpand and rowHeader.col < rowsCollapseAt)
                    tr.appendChild th
                    tbody.appendChild tr
                    rowHeader.sTr = tr

            rowHeader.clickStatus = init.rowClickStatus
            rowHeaderRows.push rowHeader


        buildValues = (tbody, rowHeaderRows, colHeaderCols) ->
            for rowHeader in rowHeaderRows
                setRowInitParams rowHeader.col
                flatRowKey = rowHeader.flatKey
                isRowSubtotal = rowHeader.descendants != 0;
                tr = if isRowSubtotal then rowHeader.sTr else rowHeader.tr
                for colHeader in colHeaderCols
                    flatColKey = colHeader.flatKey
                    aggregator = tree[flatRowKey][flatColKey] ? {value: (-> null), format: -> ""}
                    val = aggregator.value()
                    isColSubtotal = colHeader.descendants != 0;
                    setColInitParams colHeader.col
                    style = "pvtVal"
                    style += " pvtColSubtotal #{colClassOnInit}" if isColSubtotal
                    style += " pvtRowSubtotal #{rowClassOnInit}" if isRowSubtotal
                    style += if (isRowSubtotal and (rowHeader.col >= rowDisableFrom or (isRowHideOnExpand and rowHeader.col < rowsCollapseAt))) or (rowHeader.col > rowsCollapseAt) then " #{classRowHide}" else " #{classRowShow}"
                    style += if (isColSubtotal and (isColDisable or colHeader.col > colDisableAfter or (isColHideOnExpand and colHeader.col < colsCollapseAt))) or (colHeader.col > colsCollapseAt) then " #{classColHide}" else " #{classColShow}"
                    style += " row#{rowHeader.row}" +
                        " col#{colHeader.row}" +
                        " rowcol#{rowHeader.col}" +
                        " colcol#{colHeader.col}"
                    eventHandlers = getTableEventHandlers val, rowHeader.key, colHeader.key
                    td = createElement "td", style, aggregator.format(val),
                        "data-value": val,
                        "data-rownode": rowHeader.node,
                        "data-colnode": colHeader.node, eventHandlers
                    td.style.display = "none" if (rowHeader.col > rowsCollapseAt or colHeader.col > colsCollapseAt) or (isRowSubtotal and (rowHeader.col >= rowDisableFrom or (isRowHideOnExpand and rowHeader.col < rowsCollapseAt))) or (isColSubtotal and (isColDisable or colHeader.col > colDisableAfter or (isColHideOnExpand and colHeader.col < colsCollapseAt)))
                    
                    tr.appendChild td

                # buildRowTotal
                totalAggregator = rowTotals[flatRowKey]
                val = totalAggregator.value()
                style = "pvtTotal rowTotal"
                style += " pvtRowSubtotal" if isRowSubtotal 
                style += if isRowSubtotal and (rowHeader.col >= rowDisableFrom or not isDisplayOnTop or (isRowHideOnExpand and rowHeader.col < rowsCollapseAt)) then " #{classRowHide}" else " #{classRowShow}"
                style += " row#{rowHeader.row} rowcol#{rowHeader.col}"
                td = createElement "td", style, totalAggregator.format(val),
                    "data-value": val,
                    "data-row": "row#{rowHeader.row}",
                    "data-rowcol": "col#{rowHeader.col}",
                    "data-rownode": rowHeader.node, getTableEventHandlers val, rowHeader.key, []
                td.style.display = "none" if (rowHeader.col > rowsCollapseAt) or  (isRowSubtotal and (rowHeader.col >= rowDisableFrom or (isRowHideOnExpand and rowHeader.col < rowsCollapseAt)))
                tr.appendChild td

        buildColTotalsHeader = (rowAttrs, colAttrs) ->
            tr = createElement "tr"
            colspan = rowAttrs.length + (if colAttrs.length == 0 then 0 else 1)
            th = createElement "th", "pvtTotalLabel colTotal", opts.localeStrings.totals, {colspan: colspan}
            tr.appendChild th
            return tr

        buildColTotals = (tr, colHeaderCols) ->
            for h in colHeaderCols
                isColSubtotal = h.descendants != 0
                totalAggregator = colTotals[h.flatKey]
                val = totalAggregator.value()
                setColInitParams h.col
                style = "pvtVal pvtTotal colTotal"
                style += " pvtColSubtotal" if isColSubtotal
                style += " #{colClassOnInit}"
                style += " col#{h.row} colcol#{h.col}"
                td = createElement "td", style, totalAggregator.format(val),
                    "data-value": val
                    "data-for": "col#{h.col}"
                    "data-colnode": "#{h.node}", getTableEventHandlers val, [], h.key
                td.style.display = "none" if (h.col > colsCollapseAt) or (isColSubtotal and (isColDisable or h.col > colDisableAfter or (isColHideOnExpand and h.col < colsCollapseAt)))
                tr.appendChild td

        buildGrandTotal = (result, tr) ->
            totalAggregator = allTotal
            val = totalAggregator.value()
            td = createElement "td", "pvtGrandTotal", totalAggregator.format(val),
                {"data-value": val},
                getTableEventHandlers val, [], []
            tr.appendChild td
            result.appendChild tr


        hideDescendantCol = (d) ->
            $(d.th).closest 'table.pvtTable'
                .find "tbody tr td[data-colnode=\"#{d.node}\"], th[data-colnode=\"#{d.node}\"]" 
                .removeClass classColShow 
                .addClass classColHide 
                .css 'display', "none" 

        collapseShowColSubtotal = (h) ->
            $(h.th).closest 'table.pvtTable'
                .find "tbody tr td[data-colnode=\"#{h.node}\"], th[data-colnode=\"#{h.node}\"]" 
                .removeClass "#{classColExpanded} #{classColHide}"
                .addClass "#{classColCollapsed} #{classColShow}"
                .not ".pvtRowSubtotal.#{classRowHide}"
                .css 'display', "" 
            h.th.textContent = " " + arrowCollapsed + " " + h.th.getAttribute "data-colheader"
            h.th.colSpan = 1

        collapseCol = (colHeaderHeaders, colHeaderCols, c) ->
            return if isColDisable or isColDisableExpandCollapse or not colHeaderCols[c]

            h = colHeaderCols[c]
            return if h.col > colDisableAfter
            return if h.clickStatus is clickStatusCollapsed

            isColSubtotal = h.descendants != 0
            colspan = h.th.colSpan 
            for i in [1..h.descendants] when h.descendants != 0
                d = colHeaderCols[c-i]
                hideDescendantCol d
            if isColSubtotal 
                collapseShowColSubtotal h
                --colspan
            p = h.parent
            while p isnt null
                p.th.colSpan -= colspan
                p = p.parent
            h.clickStatus = clickStatusCollapsed
            colHeaderHeader = colHeaderHeaders[h.col]
            colHeaderHeader.expandedCount--
            if colHeaderHeader.expandedCount == 0
                for i in [h.col..colHeaderHeaders.length-2] when i <= colDisableAfter
                    colHeaderHeader = colHeaderHeaders[i]
                    replaceClass colHeaderHeader.th, classExpanded, classCollapsed
                    colHeaderHeader.th.textContent = " " + arrowCollapsed + " " + colHeaderHeader.th.getAttribute "data-colAttr"
                    colHeaderHeader.clickStatus = clickStatusCollapsed

        showChildCol = (ch) ->
            $(ch.th).closest 'table.pvtTable'
                .find "tbody tr td[data-colnode=\"#{ch.node}\"], th[data-colnode=\"#{ch.node}\"]" 
                .removeClass classColHide
                .addClass classColShow
                .not ".pvtRowSubtotal.#{classRowHide}"
                .css 'display', "" 

        expandHideColSubtotal = (h) ->
            $(h.th).closest 'table.pvtTable'
                .find "tbody tr td[data-colnode=\"#{h.node}\"], th[data-colnode=\"#{h.node}\"]" 
                .removeClass "#{classColCollapsed} #{classColShow}" 
                .addClass "#{classColExpanded} #{classColHide}" 
                .css 'display', "none" 
            h.th.style.display = ""

        expandShowColSubtotal = (h) ->
            $(h.th).closest 'table.pvtTable'
                .find "tbody tr td[data-colnode=\"#{h.node}\"], th[data-colnode=\"#{h.node}\"]" 
                .removeClass "#{classColCollapsed} #{classColHide}"
                .addClass "#{classColExpanded} #{classColShow}"
                .not ".pvtRowSubtotal.#{classRowHide}"
                .css 'display', "" 
            h.th.style.display = ""
            ++h.th.colSpan
            h.sTh.style.display = "" if h.sTh?

        expandChildCol = (ch) ->
            if ch.descendants != 0 and hasClass(ch.th, classColExpanded) and (isColDisable or ch.col > colDisableAfter or isColHideOnExpand)
                ch.th.style.display = ""
            else
                showChildCol ch
            expandChildCol gch for gch in ch.children if ch.clickStatus isnt clickStatusCollapsed

        expandCol = (colHeaderHeaders, colHeaderCols, c) ->
            return if isColDisable
            return if isColDisableExpandCollapse
            return if not colHeaderCols[c]

            h = colHeaderCols[c]
            return if h.col > colDisableAfter
            return if h.clickStatus is clickStatusExpanded

            isColSubtotal = h.descendants != 0
            colspan = 0
            for ch in h.children
                expandChildCol ch
                colspan += ch.th.colSpan
            h.th.colSpan = colspan
            if isColSubtotal
                replaceClass h.th, classColCollapsed, classColExpanded
                h.th.textContent = " " + arrowExpanded + " " + h.th.getAttribute "data-colHeader"
                if isColHideOnExpand
                    expandHideColSubtotal h
                    --colspan
                else
                    expandShowColSubtotal h
            p = h.parent
            while p
                p.th.colSpan += colspan
                p = p.parent
            h.clickStatus = clickStatusExpanded
            hh = colHeaderHeaders[h.col]
            ++hh.expandedCount
            if hh.expandedCount is hh.nHeaders
                replaceClass hh.th, classCollapsed, classExpanded
                hh.th.textContent = " " + arrowExpanded + " " + hh.th.getAttribute "data-colAttr"
                hh.clickStatus = clickStatusExpanded

        hideDescendantRow = (d) ->
            isRowSubtotal = d.descendants != 0
            tr = if isRowSubtotal and not isDisplayOnTop then d.sTr else d.tr 
            tr.style.display = "none"
            for tagName in ["td", "th"]
                cells = tr.getElementsByTagName tagName 
                for cell in cells
                    replaceClass cell, classRowShow, classRowHide
                    cell.style.display = "none"
            if isRowSubtotal and not isDisplayOnTop
                replaceClass d.th, classRowShow, classRowHide
                d.th.style.display = "none"

        collapseShowRowSubtotal = (h) ->
            tr = if isDisplayOnTop then h.tr else h.sTr 
            for tagName in ["td", "th"]
                cells = tr.getElementsByTagName tagName 
                for cell in cells
                    removeClass cell, "#{classRowExpanded} #{classRowHide}"
                    addClass cell, "#{classRowCollapsed} #{classRowShow}"
                    cell.style.display = "" if not hasClass cell, classColHide
            h.th.rowSpan = if isDisplayOnTop then 1 else h.descendants - h.leaves + 2
            h.th.textContent = " " + arrowCollapsed + " " + h.th.getAttribute "data-rowHeader"
            replaceClass tr, classRowExpanded, classRowCollapsed

        collapseRow = (rowHeaderHeaders, rowHeaderRows, r) ->
            h = rowHeaderRows[r]
            return if not h or h.clickStatus is clickStatusCollapsed or h.col >= rowDisableFrom or isRowDisableExpandCollapse 

            isRowSubtotal = h.descendants != 0
            oldRowspan = h.th.rowSpan
            for i in [1..h.descendants] when h.descendants != 0
                d = rowHeaderRows[r-i]
                hideDescendantRow d
            if isRowSubtotal
                collapseShowRowSubtotal h
            rowspan = oldRowspan - h.th.rowSpan
            p = h.parent
            while p
                p.th.rowSpan -= rowspan
                p = p.parent
            h.clickStatus = clickStatusCollapsed

            hh = rowHeaderHeaders.hh[h.col]
            hh.expandedCount--

            return if hh.expandedCount != 0

            for j in [h.col..rowHeaderHeaders.hh.length-2] when j < rowDisableFrom
                hh = rowHeaderHeaders.hh[j]
                replaceClass hh.th, classExpanded, classCollapsed
                hh.th.textContent = " " + arrowCollapsed + " " + hh.th.getAttribute "data-rowAttr"
                hh.clickStatus = clickStatusCollapsed

        showChildRow = (h) ->
            isRowSubtotal = h.descendants != 0
            tr = if isRowSubtotal and not isDisplayOnTop then h.sTr else h.tr 
            for tagName in ["td", "th"]
                cells = tr.getElementsByTagName tagName 
                for cell in cells
                    replaceClass cell, classRowHide, classRowShow
                    cell.style.display = "" if not hasClass cell, classColHide
            tr.style.display = ""

        expandShowRowSubtotal = (h) ->
            tr = if isDisplayOnTop then h.tr else h.sTr 
            for tagName in ["td", "th"]
                cells = tr.getElementsByTagName tagName 
                for cell in cells
                    removeClass cell, "#{classRowCollapsed} #{classRowHide}"
                    addClass cell, "#{classRowExpanded} #{classRowShow}" 
                    cell.style.display = "" if not hasClass cell, classColHide
            h.th.textContent = " " + arrowExpanded + " " + h.th.getAttribute "data-rowHeader"
            replaceClass tr, classRowCollapsed, classRowExpanded

        expandHideRowSubtotal = (h) ->
            tr = if not isDisplayOnTop then h.sTr else h.tr 
            for tagName in ["td", "th"]
                cells = tr.getElementsByTagName tagName 
                for cell in cells
                    removeClass cell, "#{classRowCollapsed} #{classRowShow}"
                    addClass cell, "#{classRowExpanded} #{classRowHide}"
                    cell.style.display = "none"
            h.th.style.display = ""
            h.th.textContent = " " + arrowExpanded + " " + h.th.getAttribute "data-rowHeader"
            replaceClass tr, classRowCollapsed, classRowExpanded

        expandChildRow = (ch) ->
            if ch.descendants != 0
                if hasClass(ch.th, classRowCollapsed)
                    ch.tr.style.display = ""
                    ch.th.style.display = ""
                    ch.th.rowSpan = ch.descendants - ch.leaves + 2
                    showChildRow ch
                else
                    ch.tr.style.display = ""
                    ch.th.style.display = ""
                    showChildRow ch if not (isRowHideOnExpand or ch.col >= rowDisableFrom)
                    expandChildRow gch for gch in ch.children if ch.clickStatus isnt clickStatusCollapsed
            else
                showChildRow ch

        expandRow = (rowHeaderHeaders, rowHeaderRows, r) ->
            h = rowHeaderRows[r]
            return if not h or h.clickStatus is clickStatusExpanded or isRowDisableExpandCollapse or h.col >= rowDisableFrom

            isRowSubtotal = h.descendants != 0
            oldRowspan = h.th.rowSpan 
            rowspan = 0
            for ch in h.children
                expandChildRow ch
                rowspan += ch.th.rowSpan
            h.th.rowSpan = if isDisplayOnTop then rowspan+1 else rowspan+2
            if isRowSubtotal
                # if isDisplayOnTop
                #    rowspan--
                if isRowHideOnExpand
                    expandHideRowSubtotal h
                else
                    expandShowRowSubtotal h
            rowspan = h.th.rowSpan - oldRowspan
            p = h.parent
            while p
                p.th.rowSpan += rowspan
                p = p.parent
            h.clickStatus = clickStatusExpanded
            hh = rowHeaderHeaders.hh[h.col]
            ++hh.expandedCount
            if hh.expandedCount == hh.nHeaders
                replaceClass hh.th, classCollapsed, classExpanded
                hh.th.textContent = " " + arrowExpanded + " " + hh.th.getAttribute "data-rowAttr"
                hh.clickStatus = clickStatusExpanded

        toggleCol = (colHeaderHeaders, colHeaderCols, c) ->
            return if not colHeaderCols[c]?

            h = colHeaderCols[c]
            if h.clickStatus is clickStatusCollapsed
                expandCol(colHeaderHeaders, colHeaderCols, c)
            else
                collapseCol(colHeaderHeaders, colHeaderCols, c)
            h.th.scrollIntoView

        toggleRow = (rowHeaderHeaders, rowHeaderRows, r) ->
            h = rowHeaderRows[r]
            return if not h

            if h.clickStatus is clickStatusCollapsed
                expandRow(rowHeaderHeaders, rowHeaderRows, r)
            else
                collapseRow(rowHeaderHeaders, rowHeaderRows, r)

        collapseColsAt = (colHeaderHeaders, colHeaderCols, colAttrs, colAttr) ->
            return if isColDisable
            if typeof colAttr is 'string'
                idx = colAttrs.indexOf colAttr
            else
                idx = colAttr
            return if idx < 0 or idx == colAttrs.length-1
            i = idx
            nAttrs = colAttrs.length-1
            while i < nAttrs and i <= colDisableAfter
                hh = colHeaderHeaders[i]
                replaceClass hh.th, classExpanded, classCollapsed
                hh.th.textContent = " " + arrowCollapsed + " " + colAttrs[i]
                hh.clickStatus = clickStatusCollapsed
                ++i
            i = 0
            nCols = colHeaderCols.length
            while i < nCols
                h = colHeaderCols[i]
                if h.col is idx and h.clickStatus isnt clickStatusCollapsed and h.th.style.display isnt "none"
                    collapseCol colHeaderHeaders, colHeaderCols, parseInt h.th.getAttribute("data-colnode")
                ++i

        expandColsAt = (colHeaderHeaders, colHeaderCols, colAttrs, colAttr) ->
            return if isColDisable
            if typeof colAttr is 'string'
                idx = colAttrs.indexOf colAttr
            else
                idx = colAttr
            return if idx < 0 or idx == colAttrs.length-1
            for i in [0..idx]
                if i <= colDisableAfter
                    hh = colHeaderHeaders[i]
                    replaceClass hh.th, classCollapsed, classExpanded
                    hh.th.textContent = " " + arrowExpanded + " " + colAttrs[i]
                    hh.clickStatus = clickStatusExpanded
                j = 0
                nCols = colHeaderCols.length
                while j < nCols
                    h = colHeaderCols[j]
                    expandCol colHeaderHeaders, colHeaderCols, j if h.col == i
                    ++j
            ++idx
            while idx < colAttrs.length-1 and idx <= colDisableAfter
                colHeaderHeader = colHeaderHeaders[idx]
                if colHeaderHeader.expandedCount == 0
                    replaceClass colHeaderHeader.th, classExpanded, classCollapsed
                    colHeaderHeader.th.textContent = " " + arrowCollapsed + " " + colAttrs[idx]
                    colHeaderHeader.clickStatus = clickStatusCollapsed
                else if colHeaderHeader.expandedCount == colHeaderHeader.nHeaders
                    replaceClass colHeaderHeader.th, classCollapsed, classExpanded
                    colHeaderHeader.th.textContent = " " + arrowExpanded + " " + colAttrs[idx]
                    colHeaderHeader.clickStatus = clickStatusExpanded
                ++idx

        collapseRowsAt = (rowHeaderHeaders, rowHeaderRows, rowAttrs, rowAttr) ->
            return if isRowDisable
            if typeof rowAttr is 'string'
                idx = rowAttrs.indexOf rowAttr
            else
                idx = rowAttr

            return if idx < 0 or idx == rowAttrs.length-1

            i = idx
            nAttrs = rowAttrs.length-1
            while i < nAttrs and i < rowDisableFrom
                h = rowHeaderHeaders.hh[i]
                replaceClass h.th, classExpanded, classCollapsed
                h.th.textContent = " " + arrowCollapsed + " " + rowAttrs[i]
                h.clickStatus = clickStatusCollapsed
                ++i
            j = 0
            nRows = rowHeaderRows.length
            while j < nRows
                h = rowHeaderRows[j]
                if h.col is idx and h.clickStatus isnt clickStatusCollapsed and h.tr.style.display isnt "none"
                    collapseRow rowHeaderHeaders, rowHeaderRows, j
                    j = j + h.descendants + 1
                else
                    ++j

        expandRowsAt = (rowHeaderHeaders, rowHeaderRows, rowAttrs, rowAttr) ->
            return if isRowDisable
            if typeof rowAttr is 'string'
                idx = rowAttrs.indexOf rowAttr
            else
                idx = rowAttr

            return if idx < 0 or idx == rowAttrs.length-1

            for i in [0..idx]
                if i < rowDisableFrom
                    hh = rowHeaderHeaders.hh[i]
                    replaceClass hh.th, classCollapsed, classExpanded
                    hh.th.textContent = " " + arrowExpanded + " " + rowAttrs[i]
                    hh.clickStatus = clickStatusExpanded
                j = 0
                nRows = rowHeaderRows.length
                while j < nRows
                    h = rowHeaderRows[j]
                    if h.col == i
                        expandRow(rowHeaderHeaders, rowHeaderRows, j)
                        j += h.descendants + 1
                    else
                        ++j
            ++idx
            while idx < rowAttrs.length-1 and idx < rowDisableFrom
                rowHeaderHeader = rowHeaderHeaders.hh[idx]
                if rowHeaderHeader.expandedCount == 0
                    replaceClass rowHeaderHeader.th, classExpanded, classCollapsed
                    rowHeaderHeader.th.textContent = " " + arrowCollapsed + " " + rowAttrs[idx]
                    rowHeaderHeader.clickStatus = clickStatusCollapsed
                else if rowHeaderHeader.expandedCount == rowHeaderHeader.nHeaders
                    replaceClass rowHeaderHeader.th, classCollapsed, classExpanded
                    rowHeaderHeader.th.textContent = " " + arrowExpanded + " " + rowAttrs[idx]
                    rowHeaderHeader.clickStatus = clickStatusExpanded
                ++idx

        toggleColHeaderHeader = (colHeaderHeaders, colHeaderCols, colAttrs, colAttr) ->
            return if isColDisable
            return if isColDisableExpandCollapse

            idx = colAttrs.indexOf colAttr
            h = colHeaderHeaders[idx]
            return if h.col > colDisableAfter
            if h.clickStatus is clickStatusCollapsed
                expandColsAt colHeaderHeaders, colHeaderCols, colAttrs, colAttr
            else
                collapseColsAt colHeaderHeaders, colHeaderCols, colAttrs, colAttr


        toggleRowHeaderHeader = (rowHeaderHeaders, rowHeaderRows, rowAttrs, rowAttr) ->
            return if isRowDisableExpandCollapse

            idx = rowAttrs.indexOf rowAttr
            th = rowHeaderHeaders.hh[idx]
            return if th.col >= rowDisableFrom
            if th.clickStatus is clickStatusCollapsed
                expandRowsAt rowHeaderHeaders, rowHeaderRows, rowAttrs, rowAttr
            else
                collapseRowsAt rowHeaderHeaders, rowHeaderRows, rowAttrs, rowAttr

        main = (rowAttrs, rowKeys, colAttrs, colKeys) ->
            rowHeaders = []
            colHeaders = []
            rowHeaderHeaders = {}
            rowHeaderRows = []
            colHeaderHeaders = []
            colHeaderCols = []

            rowHeaders = processKeys rowKeys, "pvtRowLabel" if rowAttrs.length > 0 and rowKeys.length > 0
            colHeaders = processKeys colKeys, "pvtColLabel" if colAttrs.length > 0 and colKeys.length > 0

            result = createElement "table", "pvtTable", null, {style: "display: none;"}

            thead = createElement "thead"
            result.appendChild thead

            if colAttrs.length > 0
                buildColHeaderHeaders thead, colHeaderHeaders, rowAttrs, colAttrs
                buildColHeader colHeaderHeaders, colHeaderCols, h, rowAttrs, colAttrs for h in colHeaders
                buildColHeaderHeadersClickEvents colHeaderHeaders, colHeaderCols, colAttrs

            if rowAttrs.length > 0
                buildRowHeaderHeaders thead, rowHeaderHeaders, rowAttrs, colAttrs
                buildRowTotalsHeader rowHeaderHeaders.tr, rowAttrs, colAttrs if colAttrs.length == 0

            if colAttrs.length > 0
                buildRowTotalsHeader colHeaderHeaders[0].tr, rowAttrs, colAttrs

            tbody = createElement "tbody"
            result.appendChild tbody
            buildRowHeader tbody, rowHeaderHeaders, rowHeaderRows, h, rowAttrs, colAttrs for h in rowHeaders if rowAttrs.length > 0
            buildRowHeaderHeadersClickEvents rowHeaderHeaders, rowHeaderRows, rowAttrs
            buildValues tbody, rowHeaderRows, colHeaderCols
            tr = buildColTotalsHeader rowAttrs, colAttrs
            buildColTotals tr, colHeaderCols if colAttrs.length > 0
            buildGrandTotal tbody, tr

            result.setAttribute "data-numrows", rowKeys.length
            result.setAttribute "data-numcols", colKeys.length
            result.style.display = ""

            return result

        return main rowAttrs, rowKeys, colAttrs, colKeys

    $.pivotUtilities.subtotal_renderers =
        "Table With Subtotal":  (pvtData, opts) -> SubtotalRenderer pvtData, opts
        "Table With Subtotal Bar Chart":   (pvtData, opts) -> $(SubtotalRenderer pvtData, opts).barchart()
        "Table With Subtotal Heatmap":   (pvtData, opts) -> $(SubtotalRenderer pvtData, opts).heatmap "heatmap", opts
        "Table With Subtotal Row Heatmap":   (pvtData, opts) -> $(SubtotalRenderer pvtData, opts).heatmap "rowheatmap", opts
        "Table With Subtotal Col Heatmap":  (pvtData, opts) -> $(SubtotalRenderer pvtData, opts).heatmap "colheatmap", opts

    #
    # 
    # Aggregators
    # 
    #

    usFmtPct = $.pivotUtilities.numberFormat digitsAfterDecimal:1, scaler: 100, suffix: "%"
    aggregatorTemplates = $.pivotUtilities.aggregatorTemplates;

    subtotalAggregatorTemplates =
        fractionOf: (wrapped, type="row", formatter=usFmtPct) -> (x...) -> (data, rowKey, colKey) ->
            rowKey = [] if typeof rowKey is "undefined"
            colKey = [] if typeof colKey is "undefined"
            selector: {row: [rowKey.slice(0, -1),[]], col: [[], colKey.slice(0, -1)]}[type]
            inner: wrapped(x...)(data, rowKey, colKey)
            push: (record) -> @inner.push record
            format: formatter
            value: -> @inner.value() / data.getAggregator(@selector...).inner.value()
            numInputs: wrapped(x...)().numInputs

    $.pivotUtilities.subtotalAggregatorTemplates = subtotalAggregatorTemplates

    $.pivotUtilities.subtotal_aggregators = do (tpl = aggregatorTemplates, sTpl = subtotalAggregatorTemplates) ->
        "Sum As Fraction Of Parent Row":        sTpl.fractionOf(tpl.sum(), "row", usFmtPct)
        "Sum As Fraction Of Parent Column":     sTpl.fractionOf(tpl.sum(), "col", usFmtPct)
        "Count As Fraction Of Parent Row":      sTpl.fractionOf(tpl.count(), "row", usFmtPct)
        "Count As Fraction Of Parent Column":   sTpl.fractionOf(tpl.count(), "col", usFmtPct)

