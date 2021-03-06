## This script provides summarazations, interactivity, and linking between a scatterplot matrix and a parallel coordinate plot. The scatterplot matrix has hexagonal binning as the background summarization and the parallel coordinate plot has a boxplot as the background. A large multivarate dataset is used (10,000 observations across 4 normally-distributed variables). When the user clicks on a given hexagonal bin in the scatterplot matrix, the observations inside that hexagon bin are drawn across all scatterplots. In addition, the parallel coordinate lines corresponding to those selected observations are drawn on top of the boxplot. By keeping the background summarizations constant and only updating the interactive elements superimposed, this can be achieved within seconds - even for a large dataset.

library(plotly)
library(data.table)
library(GGally)
library(hexbin)
library(htmlwidgets)
library(tidyr)
library(shiny)

ui <- shinyUI(fluidPage(
  plotlyOutput("scatMatPlot"),
  #textOutput("selectedValues"),
  plotlyOutput("boxPlot")
))


server <- shinyServer(function(input, output) {

  set.seed(1)
  bindata <- data.frame(ID = paste0("ID",1:10000), A=rnorm(10000), B=rnorm(10000), C=rnorm(10000), D=rnorm(10000))
  bindata$ID <- as.character(bindata$ID)

  ################################ Prepare scatterplot matrix
  ###########################################################

  maxVal = max(abs(bindata[,-1]))
  maxRange = c(-1*maxVal, maxVal)

  my_fn <- function(data, mapping, ...){
    x = data[,c(as.character(mapping$x))]
    y = data[,c(as.character(mapping$y))]
    h <- hexbin(x=x, y=y, xbins=5, shape=1, IDs=TRUE, xbnds=maxRange, ybnds=maxRange)
    hexdf <- data.frame (hcell2xy (h),  hexID = h@cell, counts = h@count)
    attr(hexdf, "cID") <- h@cID
    p <- ggplot(hexdf, aes(x=x, y=y, fill = counts, hexID=hexID)) + geom_hex(stat="identity") + geom_abline(intercept = 0, color = "red", size = 0.25)
    p
  }

  p <- ggpairs(bindata[,-1], lower = list(continuous = my_fn))
  pS <- p
  for(i in 2:p$nrow) {
    for(j in 1:(i-1)) {
      pS[i,j] <- p[i,j] +
        coord_cartesian(xlim = c(maxRange[1], maxRange[2]), ylim = c(maxRange[1], maxRange[2]))
    }
  }

  ggPS <- ggplotly(pS)

  myLength <- length(ggPS[["x"]][["data"]])
  for (i in 1:myLength){
    item =ggPS[["x"]][["data"]][[i]]$text[1]
    if (!is.null(item)){
      if (!startsWith(item, "co")){
        ggPS[["x"]][["data"]][[i]]$hoverinfo <- "none"
      }}
    hexHover = ggPS[["x"]][["data"]][[i]]$text
    if (!is.null(hexHover) && grepl("hexID", hexHover)){
      ggPS[["x"]][["data"]][[i]]$text <- strsplit(hexHover, "<")[[1]][1]
      ggPS[["x"]][["data"]][[i]]$t2 <- hexHover
      ggPS[["x"]][["data"]][[i]]$hoverinfo <- "text"
    }
  }

  for(i in 2:(p$nrow)) {
    for(j in 1:(p$nrow-1)) {
      bindata[[paste(i,j,sep="-")]] <- attr(pS[i,j]$data, "cID")
    }
  }

  output$scatMatPlot <- renderPlotly({
  ggPS %>% onRender("
  function(el, x, data) {

    function range(start, stop, step){
      var a=[start], b=start;
      while(b<stop){b+=step;a.push(b)}
      return a;
    };

    len = Math.sqrt(document.getElementsByClassName('cartesianlayer')[0].childNodes.length);
    AxisNames = [];
    for (i = 1; i < (len+1); i++) {
      AxisNames.push(document.getElementsByClassName('infolayer')[0].childNodes[i].textContent);
    }
    noPoint = x.data.length;

    el.on('plotly_click', function(e) {

    if (x.data.length > noPoint){
      Plotly.deleteTraces(el.id, range(noPoint, (noPoint+(len*(len-1)/2-1)), 1));
    }

    xVar = (e.points[0].xaxis._id).replace(/[^0-9]/g,'')
    if (xVar.length == 0) xVar = 1
    yVar = (e.points[0].yaxis._id).replace(/[^0-9]/g,'')
    if (yVar.length == 0) yVar = 1
    myX = len + 1 - (yVar - len * (xVar - 1))
    myY = xVar
    cN = e.points[0].curveNumber
    split1 = (x.data[cN].text).split(' ')
    hexID = (x.data[cN].t2).split(' ')[2]
    counts = split1[1].split('<')[0]
    var selRows = [];
    data.forEach(function(row){
      if(row[myX+'-'+myY]==hexID) selRows.push(row);
    });

    selID = []
    for (a=0; a<selRows.length; a++){
      selID.push(selRows[a]['ID'])
    }
    // Save selected row IDs for PCP
    Shiny.onInputChange('selID', selID);

    var Traces = [];
    var i=0;
    var k=1;
    while ((i*len+k)<=Math.pow((len-1),2)) {
      var xArr = [];
      for (a=0; a<selRows.length; a++){
        xArr.push(selRows[a][AxisNames[i]])
      }
      while ((i+k)<len){
      var yArr = [];
      for (a=0; a<selRows.length; a++){
        yArr.push(selRows[a][AxisNames[(len-k)]])
      }
      var trace = {
        x: xArr,
        y: yArr,
        mode: 'markers',
        marker: {
          color: 'orange',
          size: 7
        },
        xaxis: 'x' + (i+1),
        yaxis: 'y' + (i*len+k),
        hoverinfo: 'none'
      };
      Traces.push(trace);
      k++;
      }
      i++;
      k=1;
    }
    Plotly.addTraces(el.id, Traces);
    })}
    ", data = bindata)

})
  selID <- reactive(input$selID)

  pcpDat <- reactive(bindata[which(bindata$ID %in% selID()), c(1:(p$nrow+1))])
  #pcpDat<- bindata[which(bindata$ID %in% c("ID1","ID2","ID3")), c(1:(p$nrow+1))]
  output$selectedValues <- renderPrint({str(pcpDat())})
  colNms <- colnames(bindata[, c(2:(p$nrow+1))])

  boxDat <- bindata[, c(1:(p$nrow+1))] %>% gather(key, val, -c(ID))
  BP <- ggplot(boxDat, aes(x = key, y = val)) + geom_boxplot()
  ggBP <- ggplotly(BP)

  output$boxPlot <- renderPlotly({
  ggBP %>% onRender("
  function(el, x, data) {

  var Traces = [];

  var dLength = data.pcpDat.length
  var vLength = data.nVar
  var cNames = data.colNms

  for (a=0; a<dLength; a++){
  xArr = [];
  yArr = [];
  for (b=0; b<vLength; b++){
    xArr.push(b+1)
    yArr.push(data.pcpDat[a][cNames[b]]);
  }

  var traceHiLine = {
    x: xArr,
    y: yArr,
    mode: 'lines',
    line: {
      color: 'orange',
      width: 1
    },
    opacity: 0.9,
  }
  Traces.push(traceHiLine);
  }
  Plotly.addTraces(el.id, Traces);

}", data = list(pcpDat = pcpDat(), nVar = p$nrow, colNms = colNms))})
})

shinyApp(ui, server)


