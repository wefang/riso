load.chrlen <- function(chrlen.file, bin.width = 50){
    assign("chr.len", scan(chrlen.file), envir = .GlobalEnv)
    assign("bin.counts", ceiling(chr.len/bin.width), envir = .GlobalEnv)
    assign("bin.from", c(0, cumsum(bin.counts[1:23])), envir = .GlobalEnv)
}

#' Make GRanges object for bins.
#' @importFrom GenomicRanges GRanges
make.bins.gr <- function(chrlen.file, bin.width){
    load.chrlen(chrlen.file, bin.width)
    range.start <- unlist(lapply(bin.counts[1:23], function(count){
                                     seq(from = 1, by = bin.width, length = count)
}))
    range.end <- range.start + bin.width -1
    for (chr in 1:23){
        range.end[bin.from[chr+1]] <- chr.len[chr]
    }
    gr <- GRanges(seqnames = Rle(paste0("chr", c(1:22, "X")), bin.counts[1:23]),
                  ranges = IRanges(range.start, end = range.end))
    return(gr)
}

bp2bin <- function(bp, window = 50){
        ceiling(bp / window)
}

bin2bp <- function(bin, window = 50){
        (bin - 1) * window + 1
}

#' Imports narrowPeak files
#' @importFrom rtracklayer import.bed
import.narrowPeak <- function(f){
    extraCols.narrowPeak <- c(singnalValue = "numeric", pValue = "numeric",
                              qValue = "numeric", peak = "integer")
    import.bed(f, extraCols = extraCols.narrowPeak)
}

chr2num <- function(c){
    # earlier version need to merge with seq2num
    # does not handle Y M yet
    what <- gsub("chr", "", as.character(c))
    if (what == "X"){
        return(23)
    } else {
        return(as.numeric(what))
    }
}

#' Convert seqnames to numeric chromosome indices.
#' chrX mapped to 23; chrM and chrY mapped to NAs
seq2num <- function(seq){
    # may need to adjust if original levels are not ordered
    if (is.character(seq)) seq <- factor(seq, levels = paste0("chr", c(1:22, "X", "Y", "M")))
    l <- levels(seq)
    l <- gsub("chr", "", l)
    l[l == "X"] <- "23"

    l[l == "Y" | l == "M"] <- NA
    levels(seq) <- l
    as.numeric(seq)
}

gw2chr <- function(bins, bin.width = 200){
    # input: genome wide incices of bins
    # output: list with an item for each chromosome
    if (!exists("bin.from") | !exists("bin.counts")){
        stop("please load chr.len first")
    }
    out <- list()
    for (chr in 1:23){
        out[[chr]] <-
            bins[ (bins <= bin.from[chr + 1]) & (bins > bin.from[chr])] -
            bin.from[chr]
    }
    return(out)
}

list2gw <- function(bins.ls, bin.width = 200){
    # input: list of 23 chromosomes
    # output: output a long vector of bin indices
    if (!exists("bin.from") | !exists("bin.counts")){
        stop("please load chr.len first")
    }
    if (length(bins.ls) != 23){
        stop("list length is not 23")
    }
    unlist(lapply(1:23, function(chr) bins.ls[[chr]] + bin.from[chr]))
}

#' Convert chromosome bin indices to genome wide bin indices.
#'
#' @param chr vector of chr (Rle)
#' @param bins vector of bins
chr2gw <- function(chr, bins){
    if (!exists("bin.from") | !exists("bin.counts")){
        stop("please load chr.len first")
    }
    # check if chr is numeric
    if (!is.numeric(chr)) chr <- seq2num(chr)
    bins <- bins[!is.na(chr)]
    chr <- chr[!is.na(chr)]
    bin.from[chr] + bins
}

aveMatFac <- function(mat, fac){
    # need to be able to handle character or numeric
    if(class(fac)!="factor") fac <- factor(fac)
    rown <- length(levels(fac))
    coln <- dim(mat)[2]
    out <- matrix(, rown, coln)
    ind <- as.numeric(fac)
    for (i in 1:rown){
        out[i, ] <- colMeans(mat[ind == i, , drop = F])
    }
    rownames(out) <- levels(fac)
    return(out)
}

permutate.mat <- function(mat){
    out <- matrix(, nrow(mat), ncol(mat))
    for (i in 1:ncol(mat)){
        out[, i] <- sample(mat[, i])
    }
    return(out)
}

permutate.mat.multi <- function(...){
    mat.list <- list(...)
    # to-do: make sure elements are all matrices and have then same dimension
    n.col <- ncol(mat.list[[1]])
    n.row <- nrow(mat.list[[2]])
    out <- list()
    for (j in 1:length(mat.list)){
        out[[j]] <- matrix(, nrow(mat.list[[j]]), ncol(mat.list[[j]]))
    }
    for (i in 1:n.col){
        pidx <- sample(1:n.row)
        for (j in 1:length(mat.list)){
            out[[j]][, i] <- mat.list[[j]][pidx, i]
        }

    }
    return(out)
}

#' Count reads in bins from GeonomicAlignments object.
#' 
#' @param align GenomicAlignments (link) Object
#' @importFrom GenomicRanges seqnames  
#' @useDynLib riso riso_count_bins
countReads <- function(align, chrlen.file, bin.width, counts = NULL){
    load.chrlen(chrlen.file, bin.width)
    if (is.null(counts)) counts <- numeric(bin.from[24])
    mid <- ceiling((start(align) + end(align)) / 2)
    bin.gw <- chr2gw(seqnames(align), bp2bin(mid, bin.width))
    count_bins(counts, bin.gw)
}

#' Convert bam files to bin counts
#' 
#' @param bam.file bam file
#' @importFrom GenomicAlignments readGAlignments
bam2bin <- function(bam.file, chrlen.file, bin.width){
    alignment <- readGAlignments(bam.file)
    countReads(alignment, chrlen.file, bin.width)
}

#' Convert bam files to bin counts
#' 
#' @param bam.file bam file
#' @importFrom R.utils gunzip
#' @importFrom rtracklayer import.bed
#' @importFrom tools file_ext
ta2bin <- function(ta.file, chrlen.file, bin.width){
    #     if (file_ext(ta.file) == "gz"){
    #         ta.file <- gunzip(ta.file, temporary = T, remove = F)
    #     }
    alignment <- import.bed(ta.file)
    countReads(alignment, chrlen.file, bin.width)
}

empirical.pvalue <- function(null.vec, obs.vec, alternative = c("less", "greater", "two.sided")){
	# given a vector of null distribution, and a vector of observed statistics
    # calculate a vector of p-values
    # allows two sided p-values
    # how to handle NAs in null?

    n <- length(obs.vec)
	pvalue.vec <- numeric(n)
    alternative = match.arg(alternative)
    null.med <- median(null.vec, na.rm = T)
    for (i in 1:n){
        if(is.na(obs.vec[i])){
            pvalue.vec[i] <- NA
        } else {
            pvalue.vec[i] <-
                switch(alternative,
                       "less" = {
                           (sum(null.vec <= obs.vec[i], na.rm=T) + 1) /
                           (length(null.vec) + 1)
                       },
                       "greater" = {
                           (sum(null.vec >= obs.vec[i], na.rm=T) + 1) /
                           (length(null.vec) + 1)
                       },
                       "two.sided" = {
                           ifelse(obs.vec[i] > null.med,
                                  2 * (sum(null.vec >= obs.vec[i], na.rm=T) + 1) /
                                  (length(null.vec) + 1),
                                  2 * (sum(null.vec <= obs.vec[i], na.rm=T) + 1) /
                                  (length(null.vec) + 1)
                                  )
                       })
            pvalue.vec[i] <- pmin(pvalue.vec[1], 1)
        }
    }
	return(pvalue.vec)
}

pca.reduce <- function(mat, pcadim = NULL){
    if (is.null(pcadim)){
        sdev <- prcomp(mat)$sdev[1:20]
        x <- 1:20
        optpoint <- which.min(sapply(2:10, function(i) {
                                         x2 <- pmax(0, x - i)
                                         sum(lm(sdev ~ x + x2)$residuals ^ 2)
                                  }))
        pcadim <- optpoint + 1
    }

    tmppc <- prcomp(mat)
    pca.red <- mat %*% tmppc$rotation[, 1:pcadim]
    pca.red
}

#' wrapper of image (link) that allows plotting NAs
#' @importFrom RColorBrewer brewer.pal
image.na <- function(z,  zlim, col = colorRampPalette(brewer.pal(9,"Blues"))(1000), na.color = grey.colors(1, 0.95),
                     row.side = NULL, row.side.col = brewer.pal(8, "Dark2"),
                     row.lab = NULL, row.lab.col = NULL,
                     row.clust = F, col.clust = F,
                     outside.below.color='black', outside.above.color='white',
                     rowsep = NULL, colsep = NULL, sepcolor = grey.colors(1, 0.95), sepwidth = 0.02,
                     cellnote = F, digit.format = "%0.2f", text.col = "black", ...){

    zstep <- (zlim[2] - zlim[1]) / length(col)
    newz.below.outside <- zlim[1] - 2 * zstep
    newz.above.outside <- zlim[2] + zstep
    newz.na <- zlim[2] + 2 * zstep

    z[which(z < zlim[1])] <- newz.below.outside
    z[which(z > zlim[2])] <- newz.above.outside
    z[which(is.na(z > zlim[2]))] <- newz.na

    zlim[1] <- zlim[1] - 2 * zstep
    zlim[2] <- zlim[2] + 2 * zstep
    col <- c(outside.below.color, col[1], col, outside.above.color, na.color)
   
    if (row.clust == T){
        row.ord <- hclust(dist(z))$order
    } else {
        row.ord <- 1:nrow(z)
    }

    if (col.clust == T){
        col.ord <- hclust(dist(t(z)))$order
    } else {
        col.ord <- 1:ncol(z)
    }
    
    # side indicator
    if (!is.null(row.side)) {
        layout(matrix(1:2, 1), widths = c(1, 9))
        par(mar = c(2, 2, 2 ,2))
        image(x = 1, y = 1:length(row.side), z = matrix(row.side[col.ord], 1), zlim = c(1, max(row.side)),
              col = row.side.col, xlab = "", ylab = "", axes = F)
    }

    #     par(mar = c(2, 2, 2 ,7))
    image(x = 1:nrow(z), y = 1:ncol(z), z = z[row.ord, col.ord, drop = F], zlim=zlim, col=col, xlab = "", ylab = "", ...)
    if (!is.null(row.lab)){
        if (is.null(row.lab.col)) row.lab.col <- rep("black", length(row.lab))
        mtext(row.lab[rev(col.ord)], side = 4, at = length(row.lab):1, las = 1, col = row.lab.col[rev(col.ord)], cex = 0.4)
    }

    if (cellnote == T){
        text(x = row(z), y = col(z),
             labels = sprintf(digit.format, c(z)), col = text.col, cex = 0.6)
    }

    if (nrow(z) == 1) fine <- 0.6
    else fine <- 0.5

    if (!is.null(rowsep)){
        if (ncol(z) > 1){
            for (rsep in rowsep){
                rect(xleft = fine, ybottom = (ncol(z) + 1 - rsep) - 0.5,
                     xright = nrow(z) + 1 - fine,  ytop   = (ncol(z) + 1 - rsep) - 0.5 - sepwidth,
                     lty = 1, lwd = 1, col = sepcolor, border = sepcolor)
            }
        }
    }

    if (!is.null(colsep)){
        if (nrow(z) > 1){
            for(csep in colsep){
                rect(xleft = csep + 0.5, ybottom = 0.5,
                     xright = csep + 0.5 + 0.01, ytop = ncol(z) + 0.5,
                     lty = 1, lwd = 1, col = sepcolor, border = sepcolor)
            }

        }
    }
}

calProb <- function(mat, p, q, bg.mean, bg.sd, theta1, sigma1){

    if(is.vector(mat)) mat <- matrix(mat, 1)
    if(is.vector(bg.mean)) bg.mean <- matrix(bg.mean, 1)
    if(is.vector(bg.sd)) bg.sd <- matrix(bg.sd, 1)

    I <- dim(mat)[1]
    J <- dim(mat)[2]
    K <- dim(q)[1]

    like1 <- like0 <- matrix(, I, J)
    temp.like.sum <- temp.like.ratio <- array(, c(I, J, K))

    for (i in 1:I){
        for (j in 1:J){
            like0[i, j] <- dnorm(mat[i, j], bg.mean[i, j], bg.sd[i, j])
            like1[i, j] <- dnorm(mat[i, j], theta1[j], sigma1[j])
        }
    }

    for (i in 1:I){
        for (k in 1:K){
            for (j in 1:J){
                temp.like.sum[i, j, k] <- q[k, j] * like1[i, j] + (1 - q[k, j]) * like0[i, j]
                temp.like.ratio[i, j, k] <- q[k, j] * like1[i, j] /
                ( q[k, j] * like1[i, j] + (1 - q[k, j]) * like0[i, j] )
            }
        }
    }

    clust.like <- matrix(, I, K)
    all.like <- numeric(I)

    for (k in 1:K){
        for (i in 1:I){
            clust.like[i, k] <- log(p[k]) + sum(log(temp.like.sum[i, , k]))
        }
    }

    for (i in 1:I){
        temp <- clust.like[i, ]
        temp.max <- max(temp)
        temp <- temp - temp.max
        temp <- exp(temp)
        clust.like[i, ] <- temp / sum(temp)
        all.like[i] <- log(sum(temp)) + temp.max
    }
    loglike <- sum(all.like)

    cond.like <- array(, c(I, J, K))
    for (i in 1:I){
        for (k in 1:K){
            for (j in 1:J){
                cond.like[i, j, k] <- temp.like.ratio[i, j, k] * clust.like[i, k]
            }
        }
    }

    b.prob <- colMeans(clust.like)
    a.prob <- Reduce("+", lapply(1:K, function(k) cond.like[, , k]))

    return(list(b.prob = b.prob, a.prob = a.prob, loglike = loglike))
}

gatherPvalues <- function(da.out){
    do.call(rbind, lapply(da.out, function(out) {
                              if (class(out) == "try-error" | is.null(out$id)) {
                                  return(NULL)
                              } else {
                                  data.frame(id = out$id,
                                             isoform = out$isoform,
                                             pvalue = out$pvalue,
                                             statistics = out$test)
                              }
}))}