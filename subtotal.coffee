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

        opts.rowSubtotalDisplay = {} if not opts.rowSubtotalDisplay
        if typeof opts.rowSubtotalDisplay.disableFrom is 'undefined'
            if not opts.rowSubtotalDisplay.disableSubtotal
                if typeof opts.rowSubtotalDisplay.disableAfter is 'undefined'
                    opts.rowSubtotalDisplay.disableFrom = 9999
                else
                    opts.rowSubtotalDisplay.disableFrom = opts.rowSubtotalDisplay.disableAfter+1
            else
                opts.rowSubtotalDisplay.disableFrom = 0
        if typeof opts.rowSubtotalDisplay.collapseAt is 'undefined'
            if typeof opts.collapseRowsAt is 'undefined'
                opts.rowSubtotalDisplay.collapseAt = 9999
            else
                opts.rowSubtotalDisplay.collapseAt = opts.collapseRowsAt

        opts.colSubtotalDisplay = {} if not opts.colSubtotalDisplay
        if typeof opts.colSubtotalDisplay.disableFrom is 'undefined'
            if not opts.colSubtotalDisplay.disableSubtotal
                if typeof opts.colSubtotalDisplay.disableAfter is 'undefined'
                    opts.colSubtotalDisplay.disableFrom = 9999
                else
                    opts.colSubtotalDisplay.disableFrom = opts.colSubtotalDisplay.disableAfter+1
            else
                opts.colSubtotalDisplay.disableFrom = 0
        if typeof opts.colSubtotalDisplay.collapseAt is 'undefined'
            if typeof opts.collapseColsAt is 'undefined'
                opts.colSubtotalDisplay.collapseAt = 9999
            else
                opts.colSubtotalDisplay.collapseAt = opts.collapseColsAt

        arrowCollapsed = opts.arrowCollapsed ?= "\u25B6"
        arrowExpanded = opts.arrowExpanded ?= "\u25E2"

        colAttrs = pivotData.colAttrs
        rowAttrs = pivotData.rowAttrs
        rowKeys = pivotData.getRowKeys()
        colKeys = pivotData.getColKeys()
        tree = pivotData.tree
        rowTotals = pivotData.rowTotals
        colTotals = pivotData.colTotals
        allTotal = pivotData.allTotal

        classRowHide = "rowhide"
        classRowShow = "rowshow"
        classColHide = "colhide"
        classColShow = "colshow"
        clickStatusExpanded = "expanded"
        clickStatusCollapsed = "collapsed"
        classExpanded = "expanded"
        classCollapsed = "collapsed"


        opts.rowSubtotalDisplay.displayOnTop = true;

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
            e.setAttribute a, v for own a, v of attrs

        processKeys = (keysArr, className, opts) ->
            lastIdx = keysArr[0].length-1
            tree = children: []
            row = 0
            keysArr.reduce(
                (val0, k0) => 
                    col = 0
                    k0.reduce(
                        (acc, curVal, curIdx, arr) => 
                            if not acc[curVal]
                                key = k0.slice 0, col+1
                                acc[curVal] =
                                    row: row
                                    col: col
                                    descendants: 0
                                    children: []
                                    text: curVal
                                    key: key 
                                    flatKey: key.join String.fromCharCode(0) 
                                    firstLeaf: null 
                                    leaves: 0
                                    parent: if col isnt 0 then acc else null
                                    th: createElement "th", className, curVal
                                    childrenSpan: 0
                                acc.children.push curVal
                            if col > 0 
                                acc.descendants++
                            col++
                            if curIdx == lastIdx
                                node = tree
                                for i in [0..lastIdx-1] when lastIdx > 0
                                    node[k0[i]].leaves++
                                    if not node[k0[i]].firstLeaf 
                                        node[k0[i]].firstLeaf = acc[curVal]
                                    node = node[k0[i]]
                                return tree
                            return acc[curVal]
                        tree)
                    row++
                    return tree
                tree)
            console.warn tree
            return tree

        buildAxisHeader = (axisHeaders, col, attrs, opts) ->
            ah =
                text: attrs[col]
                expandedCount: 0
                expandables: 0
                attrHeaders: []
                clickStatus: clickStatusExpanded
                onClick: collapseAxis

            arrow = "#{arrowExpanded} "
            hClass = classExpanded
            if col >= opts.collapseAt
                arrow = "#{arrowCollapsed} "
                hClass = classCollapsed
                ah.clickStatus = clickStatusCollapsed
                ah.onClick = expandAxis
            if col == attrs.length-1 or col >= opts.disableFrom or opts.disableExpandCollapse
                arrow = ""
            ah.th = createElement "th", "pvtAxisLabel #{hClass}", "#{arrow}#{ah.text}" 
            ah.th.onclick = (event) ->
                event = event || window.event
                ah.onClick axisHeaders, col, attrs, opts
            axisHeaders.ah.push ah
            return ah 

        buildColAxisHeaders = (thead, rowAttrs, colAttrs, opts) ->
            axisHeaders =
                collapseAttrHeader: collapseCol
                expandAttrHeader: expandCol
                ah: []
            for attr, col in colAttrs
                ah = buildAxisHeader axisHeaders, col, colAttrs, opts.colSubtotalDisplay
                ah.tr = createElement "tr"
                ah.tr.appendChild createElement "th", null, null, {colspan: rowAttrs.length, rowspan: colAttrs.length} if col is 0 and rowAttrs.length isnt 0
                ah.tr.appendChild ah.th
                thead.appendChild ah.tr
            return axisHeaders

        buildRowAxisHeaders = (thead, rowAttrs, colAttrs, opts) ->
            axisHeaders =
                collapseAttrHeader: collapseRow
                expandAttrHeader: expandRow
                ah: []
                tr: createElement "tr"
            for col in [0..rowAttrs.length-1] 
                ah = buildAxisHeader axisHeaders, col, rowAttrs, opts.rowSubtotalDisplay
                axisHeaders.tr.appendChild ah.th
            if colAttrs.length != 0
                th = createElement "th"
                axisHeaders.tr.appendChild ah.th
            thead.appendChild axisHeaders.tr
            return axisHeaders

        setHeaderAttribs = (col, label, collapse, expand, attrs, opts) ->
            hProps =
                arrow: arrowExpanded
                clickStatus: clickStatusExpanded
                onClick: collapse
                class: "#{classExpanded} "
            hProps.arrow = "" if col == attrs.length-1 or col >= opts.disableFrom or opts.disableExpandCollapse
            hProps.textContent = "#{hProps.arrow} #{label}"
            return hProps

        buildColHeader = (axisHeaders, attrHeaders, h, rowAttrs, colAttrs, node, opts) ->
            # DF Recurse
            buildColHeader axisHeaders, attrHeaders, h[chKey], rowAttrs, colAttrs, node, opts for chKey in h.children
            # Process
            ah = axisHeaders.ah[h.col]
            ah.attrHeaders.push h

            h.node = node.counter
            hProps = setHeaderAttribs h.col, h.text, collapseCol, expandCol, colAttrs, opts.colSubtotalDisplay
            h.onClick = hProps.onClick

            addClass h.th, "#{classColShow} col#{h.row} colcol#{h.col} #{hProps.class}"
            h.th.setAttribute "data-colnode", h.node
            h.th.colSpan = h.childrenSpan if h.children.length isnt 0
            h.th.rowSpan = 2 if h.children.length is 0 and rowAttrs.length isnt 0
            h.th.textContent = hProps.textContent
            if h.leaves > 1 and h.col < opts.colSubtotalDisplay.disableFrom
                    ah.expandables++
                    ah.expandedCount += 1
                    h.th.colSpan++ if not opts.colSubtotalDisplay.hideOnExpand
                    h.th.onclick = (event) ->
                        event = event || window.event
                        h.onClick axisHeaders, h, opts.colSubtotalDisplay 
                    h.sTh = createElement "th", "pvtColLabelFiller col#{h.row} colcol#{h.col} #{hProps.class}"
                    h.sTh.setAttribute "data-colnode", h.node
                    h.sTh.rowSpan = colAttrs.length-h.col
                    if opts.colSubtotalDisplay.hideOnExpand and h.col < opts.colSubtotalDisplay.collapseAt
                        h.sTh.style.display = "none"
                        addClass h.sTh, classColHide
                    h[h.children[0]].tr.appendChild h.sTh if h.children.length isnt 0

            h.parent?.childrenSpan += h.th.colSpan

            h.clickStatus = hProps.clickStatus
            ah.tr.appendChild h.th
            h.tr = ah.tr
            attrHeaders.push h
            node.counter++ 


        buildRowTotalsHeader = (tr, rowAttrs, colAttrs) ->
            th = createElement "th", "pvtTotalLabel rowTotal", opts.localeStrings.totals,
                rowspan: if colAttrs.length is 0 then 1 else colAttrs.length + (if rowAttrs.length is 0 then 0 else 1)
            tr.appendChild th

        buildRowHeader = (tbody, axisHeaders, attrHeaders, h, rowAttrs, colAttrs, node, opts) ->
            # DF Recurse
            buildRowHeader tbody, axisHeaders, attrHeaders, h[chKey], rowAttrs, colAttrs, node, opts for chKey in h.children
            # Process
            ah = axisHeaders.ah[h.col]
            ah.attrHeaders.push h

            h.node = node.counter
            hProps = setHeaderAttribs h.col, h.text, collapseRow, expandRow, rowAttrs, opts.rowSubtotalDisplay
            h.onClick = hProps.onClick
            firstChild = h[h.children[0]] if h.children.length isnt 0

            addClass h.th, "#{classRowShow} row#{h.row} rowcol#{h.col} #{hProps.class}"
            h.th.setAttribute "data-rownode", h.node
            h.th.colSpan = 2 if h.col is rowAttrs.length-1 and colAttrs.length isnt 0
            h.th.rowSpan = h.childrenSpan if h.children.length isnt 0
            h.th.textContent = hProps.textContent

            if h.leaves is 1
                h.tr = firstChild.tr
                h.tr.insertBefore h.th, firstChild.th
                h.sTh = firstChild.sTh
            else
                h.tr = createElement "tr", "row#{h.row}"
                h.tr.appendChild h.th
                tbody.appendChild h.tr if h.leaves is 0

            if h.leaves > 1 and h.col < opts.rowSubtotalDisplay.disableFrom
                ++ah.expandedCount if h.col < opts.rowSubtotalDisplay.collapseAt
                if not opts.rowSubtotalDisplay.disableExpandCollapse
                    ++ah.expandables
                    addClass h.th, hProps.class
                    h.th.textContent = "#{hProps.arrow} #{h.text}"
                    h.th.onclick = (event) ->
                        event = event || window.event
                        h.onClick axisHeaders, h, opts.rowSubtotalDisplay

                h.sTh = createElement "th", "pvtRowLabelFiller row#{h.row} rowcol#{h.col} #{hProps.class}"
                h.sTh.setAttribute "data-rownode", h.node
                h.sTh.colSpan = rowAttrs.length-(h.col+1) + if colAttrs.length != 0 then 1 else 0 
                h.sTh.style.display = "none" if (opts.rowSubtotalDisplay.hideOnExpand and h.col < opts.rowSubtotalDisplay.collapseAt) or h.col > opts.rowSubtotalDisplay.collapseAt
                h.th.rowSpan++

                addClass h.tr, hProps.class
                if opts.rowSubtotalDisplay.displayOnTop
                    h.tr.appendChild h.sTh
                else
                    h.sTr = createElement "tr", "row#{h.row} #{hProps.class}"
                    h.sTr.appendChild h.sTh
                    tbody.appendChild h.sTr
                tbody.insertBefore h.tr, firstChild.tr

            h.parent?.childrenSpan += h.th.rowSpan

            h.clickStatus = hProps.clickStatus
            attrHeaders.push h
            node.counter++

        buildValues = (tbody, colAttrHeaders, rowAttrHeaders) ->
            for rowHeader in attrHeaders
                rowInit = setRowInitParams rowHeader.col
                flatRowKey = rowHeader.flatKey
                isRowSubtotal = rowHeader.descendants != 0;
                for colHeader in attrHeaders
                    flatColKey = colHeader.flatKey
                    aggregator = tree[flatRowKey][flatColKey] ? {value: (-> null), format: -> ""}
                    val = aggregator.value()
                    isColSubtotal = colHeader.descendants != 0;
                    colInit = setColInitParams colHeader.col
                    style = "pvtVal"
                    style += " pvtColSubtotal #{colInit.colClass}" if isColSubtotal
                    style += " pvtRowSubtotal #{rowInit.rowClass}" if isRowSubtotal
                    style += if (isRowSubtotal and (rowHeader.col >= rowDisableFrom or (isRowHideOnExpand and rowHeader.col < opts.rowSubtotalDisplay.collapseAt))) or (rowHeader.col > opts.rowSubtotalDisplay.collapseAt) then " #{classRowHide}" else " #{classRowShow}"
                    style += if (isColSubtotal and (isColDisable or colHeader.col > colDisableAfter or (isColHideOnExpand and colHeader.col < opts.colSubtotalDisplay.collapseAt))) or (colHeader.col > opts.colSubtotalDisplay.collapseAt) then " #{classColHide}" else " #{classColShow}"
                    style += " row#{rowHeader.row}" +
                        " col#{colHeader.row}" +
                        " rowcol#{rowHeader.col}" +
                        " colcol#{colHeader.col}"
                    eventHandlers = getTableEventHandlers val, rowHeader.key, colHeader.key
                    td = createElement "td", style, aggregator.format(val),
                        "data-value": val,
                        "data-rownode": rowHeader.node,
                        "data-colnode": colHeader.node, eventHandlers
                    if not isDisplayOnTop
                        td.style.display = "none" if (rowHeader.col > opts.rowSubtotalDisplay.collapseAt or colHeader.col > opts.colSubtotalDisplay.collapseAt) or (isRowSubtotal and (rowHeader.col >= rowDisableFrom or (isRowHideOnExpand and rowHeader.col < opts.rowSubtotalDisplay.collapseAt))) or (isColSubtotal and (isColDisable or colHeader.col > colDisableAfter or (isColHideOnExpand and colHeader.col < opts.colSubtotalDisplay.collapseAt)))
                    
                    rowHeader.tr.appendChild td

                # buildRowTotal
                totalAggregator = rowTotals[flatRowKey]
                val = totalAggregator.value()
                style = "pvtTotal rowTotal #{rowInit.rowClass}"
                style += " pvtRowSubtotal " if isRowSubtotal 
                style += if isRowSubtotal and (rowHeader.col >= rowDisableFrom or not isDisplayOnTop or (isRowHideOnExpand and rowHeader.col < opts.rowSubtotalDisplay.collapseAt)) then " #{classRowHide}" else " #{classRowShow}"
                style += " row#{rowHeader.row} rowcol#{rowHeader.col}"
                td = createElement "td", style, totalAggregator.format(val),
                    "data-value": val,
                    "data-row": "row#{rowHeader.row}",
                    "data-rowcol": "col#{rowHeader.col}",
                    "data-rownode": rowHeader.node, getTableEventHandlers val, rowHeader.key, []
                if not isDisplayOnTop
                    td.style.display = "none" if (rowHeader.col > opts.rowSubtotalDisplay.collapseAt) or  (isRowSubtotal and (rowHeader.col >= rowDisableFrom or (isRowHideOnExpand and rowHeader.col < opts.rowSubtotalDisplay.collapseAt)))
                rowHeader.tr.appendChild td

        buildColTotalsHeader = (rowAttrs, colAttrs) ->
            tr = createElement "tr"
            colspan = rowAttrs.length + (if colAttrs.length == 0 then 0 else 1)
            th = createElement "th", "pvtTotalLabel colTotal", opts.localeStrings.totals, {colspan: colspan}
            tr.appendChild th
            return tr

        buildColTotals = (tr, attrHeaders) ->
            for h in attrHeaders when h.leaves isnt 1
                colInit = setColInitParams h.col
                clsNames = "pvtVal pvtTotal colTotal #{colInit.colClass} col#{h.row} colcol#{h.col}"
                clsNames += " pvtColSubtotal" if h.children.length isnt 0 
                totalAggregator = colTotals[h.flatKey]
                val = totalAggregator.value()
                td = createElement "td", clsNames, totalAggregator.format(val),
                    "data-value": val
                    "data-for": "col#{h.col}"
                    "data-colnode": "#{h.node}", getTableEventHandlers val, [], h.key
                td.style.display = "none" if (h.col > opts.colSubtotalDisplay.collapseAt) or (h.children.length isnt 0 and (isColDisable or h.col > colDisableAfter or (isColHideOnExpand and h.col < opts.colSubtotalDisplay.collapseAt)))
                tr.appendChild td

        buildGrandTotal = (result, tr) ->
            totalAggregator = allTotal
            val = totalAggregator.value()
            td = createElement "td", "pvtGrandTotal", totalAggregator.format(val),
                {"data-value": val},
                getTableEventHandlers val, [], []
            tr.appendChild td
            result.appendChild tr

        adjustAxisHeader = (axisHeaders, col, opts) ->
            ah = axisHeaders.ah[col]
            if ah.expandedCount is 0
                replaceClass ah.th, classExpanded, classCollapsed
                ah.th.textContent = " #{arrowCollapsed} #{ah.text}"
                ah.clickStatus = clickStatusCollapsed
                ah.onClick = expandAxis
            else if ah.expandedCount is ah.expandables
                replaceClass ah.th, classCollapsed, classExpanded
                ah.th.textContent = " #{arrowExpanded} #{ah.text}"
                ah.clickStatus = clickStatusExpanded
                ah.onClick = collapseAxis

        hideDescendantCol = (d) ->
            $(d.th).closest 'table.pvtTable'
                .find "tbody tr td[data-colnode=\"#{d.node}\"], th[data-colnode=\"#{d.node}\"]" 
                .removeClass classColShow 
                .addClass classColHide 
                .css 'display', "none" 

        collapseShowColSubtotal = (h, opts) ->
            exclude = ".#{classRowHide}"
            exclude += ", .#{classColHide}" if not opts.hideOnExpand
            $(h.th).closest 'table.pvtTable'
                .find "tbody tr td[data-colnode=\"#{h.node}\"], th[data-colnode=\"#{h.node}\"]" 
                .removeClass classExpanded
                .addClass classCollapsed
                .not exclude
                .removeClass classColHide
                .addClass classColShow
                .css 'display', "" 
            h.th.textContent = " #{arrowCollapsed} #{h.text}"
            h.th.colSpan = 1

        collapseChildCol = (ch, h) ->
            collapseChildCol ch[chKey], h for chKey in ch.children when hasClass ch[chKey].th, classColShow
            hideDescendantCol ch

        collapseCol = (axisHeaders, h, opts) ->
            colSpan = h.th.colSpan - 1
            collapseChildCol h[chKey], h for chKey in h.children when hasClass h[chKey].th, classColShow
            collapseShowColSubtotal h, opts
            if hasClass h.th, classColShow
                p = h.parent
                while p
                    p.th.colSpan -= colSpan
                    p = p.parent
            h.clickStatus = clickStatusCollapsed
            h.onClick = expandCol
            axisHeaders.ah[h.col].expandedCount--
            adjustAxisHeader axisHeaders, h.col, opts

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
                .removeClass "#{classCollapsed} #{classColShow}" 
                .addClass "#{classExpanded} #{classColHide}" 
                .css 'display', "none" 
            replaceClass h.th, classColHide, classColShow
            h.th.style.display = ""
            h.th.textContent = " #{arrowExpanded} #{h.text}"

        expandShowColSubtotal = (h) ->
            $(h.th).closest 'table.pvtTable'
                .find "tbody tr td[data-colnode=\"#{h.node}\"], th[data-colnode=\"#{h.node}\"]" 
                .removeClass "#{classCollapsed} #{classColHide}"
                .addClass "#{classExpanded} #{classColShow}"
                .not ".pvtRowSubtotal.#{classRowHide}"
                .css 'display', "" 
            h.th.colSpan++
            h.th.textContent = " #{arrowExpanded} #{h.text}"
            h.th.style.display = ""
            h.sTh.style.display = "" if h.sTh?

        expandChildCol = (ch, opts) ->
            if ch.leaves isnt 0 and (ch.col >= opts.disableFrom or (ch.clickStatus is clickStatusCollapsed and not opts.hideOnExpand) or (ch.clickStatus is clickStatusExpanded and opts.hideOnExpand))
                replaceClass ch.th, classColHide, classColShow
                ch.th.textContent = " #{arrowExpanded} #{ch.text} "
                ch.th.style.display = ""
            else
                showChildCol ch
                if ch.sTh and ch.clickStatus is clickStatusExpanded and opts.hideOnExpand
                    replaceClass ch.sTh, classColShow, classColHide
                    ch.sTh.style.display = "none"
            expandChildCol ch[chKey], opts for chKey in ch.children if ch.clickStatus is clickStatusExpanded
            
        expandCol = (axisHeaders, h, opts) ->
            colSpan = 0
            for chKey in h.children
                ch = h[chKey]
                expandChildCol ch, opts
                colSpan += ch.th.colSpan
            h.th.colSpan = colSpan

            if opts.hideOnExpand
                expandHideColSubtotal h
                --colSpan
            else
                expandShowColSubtotal h
            p = h.parent
            while p
                p.th.colSpan += colSpan
                p = p.parent
            h.clickStatus = clickStatusExpanded
            h.onClick = collapseCol
            axisHeaders.ah[h.col].expandedCount++
            adjustAxisHeader axisHeaders, h.col, opts

        hideDescendantRow = (d, opts) ->
            d.tr.style.display = "none" if opts.displayOnTop
            cells = d.tr.getElementsByTagName "td"
            replaceClass cell, classRowShow, classRowHide for cell in cells
            if not opts.displayOnTop
                cell.style.display = "none" for cell in cells
                d.sTh.style.display = "none" if d.sTh
                d.th.style.display = "none"

        collapseShowRowSubtotal = (h) ->
            cells = h.tr.getElementsByTagName "td" 
            for cell in cells
                removeClass cell, "#{classExpanded} #{classRowHide}"
                addClass cell, "#{classCollapsed} #{classRowShow}"
                cell.style.display = "" if not hasClass cell, classColHide
            replaceClass h.th, classExpanded, classCollapsed
            h.th.style.display = "" 
            h.th.textContent = " #{arrowCollapsed} #{h.text}"
            h.th.rowSpan = 1
            replaceClass h.sTh, classExpanded, classCollapsed
            h.sTh.style.display = ""
            replaceClass h.tr, classExpanded, classCollapsed
            h.tr.style.display = ""

        collapseChildRow = (ch, h, opts) ->
            collapseChildRow ch[chKey], h, opts for chKey in ch.children
            hideDescendantRow ch, opts

        collapseRow = (axisHeaders, h, opts) ->
            rowSpan = h.th.rowSpan - 1
            collapseChildRow h[chKey], h, opts for chKey in h.children
            collapseShowRowSubtotal h
            if opts.displayOnTop
                p = h.parent
                while p
                    p.th.rowSpan -= rowSpan
                    p = p.parent
            h.clickStatus = clickStatusCollapsed
            h.onClick = expandRow
            axisHeaders.ah[h.col].expandedCount--
            adjustAxisHeader axisHeaders, h.col, opts

        showChildRow = (h, opts) ->
            cells = h.tr.getElementsByTagName "td" 
            for cell in cells
                replaceClass cell, classRowHide, classRowShow
            if not opts.displayOnTop
                cell.style.display = "" for cell in cells when not hasClass cell, classColHide
                h.th.style.display = "" if h.descendants == 0 or h.clickStatus isnt clickStatusCollapsed
                h.sTh.style.display = "" if h.sTh
            h.tr.style.display = ""

        expandShowRowSubtotal = (h) ->
            cells = h.tr.getElementsByTagName "td"
            for cell in cells
                removeClass cell, "#{classCollapsed} #{classRowHide}"
                addClass cell, "#{classExpanded} #{classRowShow}" 
                cell.style.display = "" if not hasClass cell, classColHide
            replaceClass h.th, classCollapsed, classExpanded
            h.th.textContent = " #{arrowExpanded} #{h.text}"
            h.th.style.display = ""
            h.sTh.style.display = ""
            replaceClass h.sTh, classCollapsed, classExpanded
            replaceClass h.tr, classCollapsed, classExpanded
            h.tr.style.display = ""

        expandHideRowSubtotal = (h) ->
            cells = h.tr.getElementsByTagName "td"
            for cell in cells
                removeClass cell, "#{classCollapsed} #{classRowShow}"
                addClass cell, "#{classExpanded} #{classRowHide}"
            h.th.textContent = " #{arrowExpanded} #{h.text}"
            h.th.style.display = ""
            replaceClass h.tr, classCollapsed, classExpanded
            h.tr.style.display = "none"

        expandChildRow = (ch, opts) ->
            showChildRow ch, opts
            expandChildRow ch[chKey], opts for chKey in ch.children when ch.clickStatus is clickStatusExpanded

        expandRow = (axisHeaders, h, opts) ->
            rowSpan = 0
            for chKey in h.children
                ch = h[chKey]
                expandChildRow ch, opts
                rowSpan += ch.th.rowSpan
            if h.leaves > 1 
                if opts.hideOnExpand
                    expandHideRowSubtotal h
                else
                    expandShowRowSubtotal h
            if opts.displayOnTop
                h.th.rowSpan = rowSpan+1
                p = h.parent
                while p
                    p.th.rowSpan += rowSpan
                    p = p.parent
            h.clickStatus = clickStatusExpanded
            h.onClick = collapseRow
            axisHeaders.ah[h.col].expandedCount++
            adjustAxisHeader axisHeaders, h.col, opts
    
        collapseAxis = (axisHeaders, col, attrs, opts) ->
            collapsible = attrs.length-2
            return if col > collapsible
            axisHeaders.collapseAttrHeader axisHeaders, h, opts for h in axisHeaders.ah[i].attrHeaders when h.clickStatus is clickStatusExpanded and h.leaves > 1 for i in [collapsible..col] by -1

        expandAxis = (axisHeaders, col, attrs, opts) ->
            axisHeaders.expandAttrHeader axisHeaders, h, opts for h in axisHeaders.ah[i].attrHeaders when h.clickStatus is clickStatusCollapsed and h.leaves > 1 for i in [0..col] 

        main = (rowAttrs, rowKeys, colAttrs, colKeys) ->
            rowAttrHeaders = []
            colAttrHeaders = []

            colKeyHeaders = processKeys colKeys, "pvtColLabel" if colAttrs.length isnt 0 and colKeys.length isnt 0
            rowKeyHeaders = processKeys rowKeys, "pvtRowLabel" if rowAttrs.length isnt 0 and rowKeys.length isnt 0

            result = createElement "table", "pvtTable", null, {style: "display: none;"}

            thead = createElement "thead"
            result.appendChild thead

            if colAttrs.length isnt 0
                colAxisHeaders = buildColAxisHeaders thead, rowAttrs, colAttrs, opts
                node = counter: 0
                buildColHeader colAxisHeaders, colAttrHeaders, colKeyHeaders[chKey], rowAttrs, colAttrs, node, opts for chKey in colKeyHeaders.children
                buildRowTotalsHeader colAxisHeaders.ah[0].tr, rowAttrs, colAttrs

            tbody = createElement "tbody"
            result.appendChild tbody
            if rowAttrs.length isnt 0
                rowAxisHeaders = buildRowAxisHeaders thead, rowAttrs, colAttrs, opts
                buildRowTotalsHeader rowAxisHeaders.tr, rowAttrs, colAttrs if colAttrs.length is 0
                node = counter: 0
                buildRowHeader tbody, rowAxisHeaders, rowAttrHeaders, rowKeyHeaders[chKey], rowAttrs, colAttrs, node, opts for chKey in rowKeyHeaders.children

            # buildValues tbody, colAttrHeaders, rowAttrHeaders
            tr = buildColTotalsHeader rowAttrs, colAttrs
            # buildColTotals tr, colAttrHeaders if colAttrs.length > 0
            buildGrandTotal tbody, tr

            collapseAxis colAxisHeaders, opts.colSubtotalDisplay.collapseAt, colAttrs, opts
            collapseAxis rowAxisHeaders, opts.rowSubtotalDisplay.collapseAt, rowAttrs, opts

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
    # Aggregators
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

