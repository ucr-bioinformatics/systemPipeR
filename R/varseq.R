######################
## Filter VCF files ##
######################
filterVars <- function(args, filter, varcaller, organism) {
	if(class(args)!="SYSargs") stop("Argument 'args' needs to be of class SYSargs")
	if(all(!c("gatk", "bcftools", "vartools") %in% varcaller)) stop("Argument 'varcaller' needs to be assigned 'gatk' or 'bcftools'")
	if(length(filter)!=1 | !is.character(filter)) stop("Argument 'filter' needs to character vector of length 1")
	for(i in seq(along=args)) {
		vcf <- readVcf(infile1(args)[i], organism)
		vr <- as(vcf, "VRanges")
		if(varcaller=="gatk") {
            ## Apply filter
			vrfilt <- vr[eval(parse(text=filter)), ]
		}
		if(varcaller=="bcftools") {
			vrsambcf <- vr
			vr <- unlist(values(vr)$DP4)
			vr <- matrix(vr, ncol=4, byrow=TRUE)
            ## Fix missing depth info in VRanges generated from VCF of bcftools
            totalDepth(vrsambcf) <- as.integer(values(vrsambcf)$DP)
            refDepth(vrsambcf) <- rowSums(vr[,1:2])
            altDepth(vrsambcf) <- rowSums(vr[,3:4])
            ## Apply filter
			vrfilt <- vrsambcf[eval(parse(text=filter)), ]
		}
		if(varcaller=="vartools") {
            ## Apply filter
			tmp <- as.data.frame(values(vr)); tmp[is.na(tmp)]<-0
            values(vr) <- tmp
            vrfilt <- vr[eval(parse(text=filter)), ]
		}
		vcffilt <- asVCF(vrfilt)
		writeVcf(vcffilt, outfile1(args)[i], index = TRUE)
		print(paste("Generated file", i, gsub(".*/", "", outpaths(args)[i])))
	}
}
## Usage for GATK:
# filter <- "totalDepth(vr) >= 20 & (altDepth(vr) / totalDepth(vr) >= 0.8) & rowSums(softFilterMatrix(vr))==6"
# filterVars(args, filter, varcaller="gatk", organism="Pinfest")
## Usage for BCFtools:
# filter <- "rowSums(vr) >= 20 & (rowSums(vr[,3:4])/rowSums(vr[,1:4]) >= 0.8)"
# filterVars(args, filter, varcaller="bcftools", organism="Pinfest")

#################
## VAR Reports ##
#################
## Report for locatVariants() where data for each variant is collapsed to a single line.
.allAnnot <- function(x, vcf){
	rd <- rowRanges(vcf)
	## Make variant calls in rd unique by collapsing duplicated ones
	VARID <- VARID <- unique(names(rd))
	REF <- tapply(as.character(values(rd)$REF), factor(names(rd)), function(i) paste(unique(i), collapse=" "))
	ALT <- tapply(as.character(unlist(values(rd)$ALT)), factor(names(rd)), function(i) paste(unique(i), collapse=" "))
	QUAL <- tapply(values(rd)$QUAL, factor(names(rd)), function(i) paste(unique(i), collapse=" "))
	
	## fix names field in x if incomplete
	if(any(names(x)=="")) {
		index <- unique(names(rd)); names(index) <- gsub("_.*", "", index)
		names(x) <- index[paste(as.character(seqnames(x)), ":", start(x), sep="")]
	}

	## Make annotated variant calls in x unique by collapsing duplicated ones
	LOCATION <- tapply(as.character(values(x)$LOCATION), as.factor(names(x)), function(i) paste(i, collapse=" "))
	GENEID <- tapply(values(x)$GENEID, factor(names(x)), function(i) paste(unique(i), collapse=" "))
	
	## Assemble results in data.frame
	df <- data.frame(VARID=VARID,
			REF=REF[VARID],
			ALT=ALT[VARID],
			QUAL=QUAL[VARID],
			LOCATION=LOCATION[VARID],
			GENEID=GENEID[VARID])
	df[,"LOCATION"] <- gsub("NA", "", df$LOCATION)
	df[,"GENEID"] <- gsub("NA", "", df$GENEID)
	return(df)
}
## Usage:
# allvar <- locateVariants(rd, txdb, AllVariants())
# varreport <- .allAnnot(allvar, vcf)

## Report for predictCoding() where data for each variant if collapsed to one line.
.codingReport <- function(x, txdb) {
	txids <- values(transcripts(txdb))$tx_name; names(txids) <- values(transcripts(txdb))$tx_id
	#myf <- as.factor(names(values(x)$CDSLOC))
	myf <- as.factor(names(x))
	if(length(myf)>0) {
		df <- data.frame(VARID=tapply(as.character(myf), myf, unique), 
        	                 Strand=tapply(as.character(strand(x)), myf, unique),
			         Consequence=tapply(as.character(values(x)$CONSEQUENCE), myf, function(i) paste(unique(i), collapse=" ")),
		       		 Codon=tapply(paste(start(values(x)$CDSLOC), "_", as.character(values(x)$REFCODON), "/", as.character(values(x)$VARCODON), sep=""), myf, paste, collapse=" "), 
		       	         AA=tapply(paste(sapply(values(x)$PROTEINLOC, paste, collapse="_"), "_", as.character(values(x)$REFAA), "/", as.character(values(x)$VARAA), sep=""), myf, paste, collapse=" "), 
		                 TXIDs=tapply(txids[values(x)$TXID], myf, paste, collapse=" "), 
		                 GENEIDcode=tapply(values(x)$GENEID, myf, function(i) paste(unique(i), collapse=" ")))
	} else {
		df <- data.frame(VARID=NA, Strand=NA, Consequence=NA, Codon=NA, AA=NA, TXIDs=NA, GENEIDcode=NA)[FALSE,,drop=FALSE]
	}
	return(df)	      
}
## Usage:
# codereport <- predictCoding(vcf, txdb, seqSource=fa)
# codereport <- .codingReport(coderport, txdb)

####################
## Variant Report ##
####################
variantReport <- function(args, txdb, fa, organism) {
	if(class(args)!="SYSargs") stop("Argument 'args' needs to be of class SYSargs")
	for(i in seq(along=args)) {
		## Import VCF
		vcf <- readVcf(infile1(args)[i], organism)
	
		## Adding genomic context for all annotation features
		allvar <- locateVariants(vcf, txdb, AllVariants())
		varreport <- .allAnnot(allvar, vcf)
		## Consequences for coding variants
		coding <- predictCoding(vcf, txdb, seqSource=fa)
		codereport <- .codingReport(coding, txdb)
	
		## Add variant statistics to annotation report
		vr <- as(vcf, "VRanges")
		varid <- paste(as.character(seqnames(vr)), ":", start(vr), "_", ref(vr), "/", alt(vr), sep="")
		vrdf <- data.frame(row.names=varid, as.data.frame(vr))
		vrdf <- vrdf[,c("totalDepth", "refDepth", "altDepth")]
	
		## Combine and export results
		fullreport <- cbind(varreport, codereport[rownames(varreport),-1])
		fullreport <- cbind(VARID=as.character(fullreport[,1]), vrdf[as.character(rownames(fullreport)),], fullreport[,-1])
		fullreport <- data.frame(lapply(fullreport, as.character), stringsAsFactors=FALSE)
		write.table(fullreport, file=outfile1(args)[i], row.names=FALSE, quote=FALSE, sep="\t", na="")
		print(paste("Generated file", i, gsub(".*/", "", outfile1(args)[i])))
	}
}
## Usage:
# variantReport(args=args, txdb=txdb, fa=fa, organism="Pinfest")

#############################
## Combine Variant Reports ##
#############################
combineVarReports <- function(args, filtercol, ncol=15) {
	if(class(args)!="SYSargs") stop("Argument 'args' needs to be of class SYSargs")
	samples <- names(outpaths(args))
	for(i in seq(along=samples)) {
		if(i==1) {
			varDF <- read.delim(outpaths(args)[i], colClasses=rep("character", ncol))
			varDF <- cbind(Sample=samples[i], varDF) 
			if(filtercol[1]!="All") varDF <- varDF[varDF[,names(filtercol)]==filtercol,]
		} else {
			tmpDF <- read.delim(outpaths(args)[i])
			tmpDF <- read.delim(outpaths(args)[i], colClasses=rep("character", ncol))
			tmpDF <- cbind(Sample=samples[i], tmpDF) 
			if(filtercol[1]!="All") tmpDF <- tmpDF[tmpDF[,names(filtercol)]==filtercol,]
			varDF <- rbind(as.data.frame(as.matrix(varDF)), as.data.frame(as.matrix(tmpDF)))
		}
		varDF <- varDF[order(varDF$VARID),]
	}
	return(varDF)
}
## Usage:
# args <- systemArgs(sysma="annotate_vars.param", mytargets="targets_gatk_filtered.txt")
# combineDF <- combineVarReports(args, filtercol=c(Consequence="nonsynonymous"))

###########################################
## Create summary statistics of variants ##
###########################################
varSummary <- function(args) {
	if(class(args)!="SYSargs") stop("Argument 'args' needs to be of class SYSargs")
	for(i in seq(along=args)) {
		annotDF <- read.delim(outpaths(args)[i])
		count <- c(all=length(annotDF[,1]),
			   table(unlist(strsplit(as.character(annotDF$LOCATION), " "))),
			   table(unlist(strsplit(as.character(annotDF$Consequence), " "))))
		if(i==1) {
			countDF <- data.frame(count)
		} else {
			countDF <- cbind(countDF, count[rownames(countDF)])
		}
	}
	countDF[is.na(countDF)] <- 0
	colnames(countDF) <- names(outpaths(args))
	return(countDF)
}
## Usage:
# args <- systemArgs(sysma="annotate_vars.param", mytargets="targets_gatk_filtered.txt")
# varSummaryDF <- varSummary(args)


