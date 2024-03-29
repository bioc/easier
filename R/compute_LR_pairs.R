#' Compute ligand-receptor pair weights from TPM bulk gene expression
#'
#' Quantifies ligand-receptor interactions in the tumor microenvironment
#' from TPM bulk gene expression (Lapuente-Santana et al., Patterns, 2021)
#' by using prior knowledge coming from ligand-receptor pair annotations
#' from the database of Ramilowski (Ramilowski et al., Nat Commun, 2015).
#' Each ligand-receptor weight is defined as the minimum of the log2(TPM+1)
#' expression of the ligand and the receptor.
#'
#' @references Oscar Lapuente-Santana, Maisa van Genderen,
#' Peter A. J. Hilbers, Francesca Finotello, and Federica Eduati.
#' 2021. Interpretable Systems Biomarkers Predict Response to
#' Immune-Checkpoint Inhibitors. Patterns, 100293.
#' https://doi.org/10.1016/j.patter.2021.100293.
#'
#' @references Ramilowski, J., Goldberg, T., Harshbarger, J. et al.
#' A draft network of ligand–receptor-mediated multicellular signalling
#' in human. Nat Commun 6, 7866 (2015). https://doi.org/10.1038/ncomms8866
#'
#' @importFrom stats na.exclude
#' @importFrom utils head tail
#' @importFrom easierData get_intercell_networks get_group_lrpairs
#'
#' @param RNA_tpm A data.frame containing TPM values with HGNC symbols
#' in rows and samples in columns.
#' @param cancer_type A string detailing the cancer type whose
#' ligand-receptor pairs network will be used.
#' A pan-cancer network is selected by default, whose network represents
#' the union of all ligand-receptor pairs present across the 18 cancer
#' types studied in Lapuente-Santana et al., Patterns, 2021.
#' @param verbose A logical value indicating whether to display messages
#' about the number of ligand-receptor genes found in the gene expression
#' data provided.
#'
#' @return A matrix of weights with samples in rows and ligand-receptor
#' pairs in columns.
#'
#' @export
#'
#' @examples
#' # using a SummarizedExperiment object
#' library(SummarizedExperiment)
#' # Using example exemplary dataset (Mariathasan et al., Nature, 2018)
#' # from easierData. Original processed data is available from
#' # IMvigor210CoreBiologies package.
#' library("easierData")
#'
#' dataset_mariathasan <- easierData::get_Mariathasan2018_PDL1_treatment()
#' RNA_tpm <- assays(dataset_mariathasan)[["tpm"]]
#'
#' # Select a subset of patients to reduce vignette building time.
#' pat_subset <- c(
#'   "SAM76a431ba6ce1", "SAMd3bd67996035", "SAMd3601288319e",
#'   "SAMba1a34b5a060", "SAM18a4dabbc557"
#' )
#' RNA_tpm <- RNA_tpm[, colnames(RNA_tpm) %in% pat_subset]
#'
#' # Computation of ligand-receptor pair weights
#' lrpair_weights <- compute_LR_pairs(
#'   RNA_tpm = RNA_tpm,
#'   cancer_type = "pancan"
#' )
#' lrpair_weights[1:5, 1:5]
compute_LR_pairs <- function(RNA_tpm = NULL,
                             cancer_type = "pancan",
                             verbose = TRUE) {
  # Some checks
  if (is.null(RNA_tpm)) stop("TPM gene expression data not found")

  # Retrieve internal data
  intercell_networks <- suppressMessages(easierData::get_intercell_networks())
  group_lrpairs <- suppressMessages(easierData::get_group_lrpairs())

  # Check cancer_type network is available if pancancer is not used
  if (cancer_type %in% names(intercell_networks) == FALSE) {
    stop("The specified cancer type is not included in the list of
             ligand-receptor networks")
  }

  # Adding NSCLC network (*to change in EasierData intercell network *)
  if (cancer_type == "NSCLC") {
    LUAD_intercell <- intercell_networks$LUAD
    LUSC_intercell <- intercell_networks$LUSC
    LUAD_array <- vapply(seq_len(nrow(LUAD_intercell)), function(X) {
      LUAD_intercell$cell1 <- as.character(LUAD_intercell$cell1)
      LUAD_intercell$cell2 <- as.character(LUAD_intercell$cell2)
      LUAD_array <- paste(LUAD_intercell[X, , drop = TRUE], collapse = "_")
    }, FUN.VALUE = character(length(1)))
    LUSC_array <- vapply(seq_len(nrow(LUSC_intercell)), function(X) {
      LUSC_intercell$cell1 <- as.character(LUSC_intercell$cell1)
      LUSC_intercell$cell2 <- as.character(LUSC_intercell$cell2)
      LUSC_array <- paste(LUSC_intercell[X, , drop = TRUE], collapse = "_")
    }, FUN.VALUE = character(length(1)))
    NSCLC_array <- union(LUAD_array, LUSC_array)
    NSCLC_intercell <- as.data.frame(
      do.call(rbind, lapply(seq_len(length(NSCLC_array)), function(X) {
        tmp <- unlist(strsplit(NSCLC_array[X], split = "_"))
        names(tmp) <- colnames(LUAD_intercell)
        return(tmp)
      }))
    )
    intercell_networks[["NSCLC"]] <- NSCLC_intercell
  }

  # Gene expression data (log2 transformed)
  gene_expr <- log2(RNA_tpm + 1)
  genes <- rownames(gene_expr)

  # HGNC symbols are required
  if (any(grep("ENSG00000", genes))) {
    stop("Hgnc gene symbols are required",
      call. = FALSE
    )
  }

  gene_expr <- as.data.frame(gene_expr)

  # Cancer-specific LR pairs network
  intercell_network <- intercell_networks[[cancer_type]]
  LR_pairs <- unique(paste0(intercell_network$ligands, "_", intercell_network$receptors))

  # check what is the percentage of genes we have in our data
  all_lrpairs_genes <- unique(c(intercell_network$ligands, intercell_network$receptors))
  genes_kept <- intersect(rownames(gene_expr), all_lrpairs_genes)
  genes_left <- setdiff(all_lrpairs_genes, rownames(gene_expr))

  # check what is the percentage of regulated transcripts that we have in our data
  message(
    "LR signature genes found in data set: ", length(genes_kept), "/",
    length(all_lrpairs_genes),
    " (", round(length(genes_kept) / length(all_lrpairs_genes), 3) * 100,
    "%)"
  )

  # Compute L-R pairs
  LR_pairs_computed <- do.call(rbind, lapply(
    seq_len(length(LR_pairs)),
    function(x) {
      ligand <- vapply(strsplit(LR_pairs[x], split = "_", fixed = TRUE),
        utils::head, 1,
        FUN.VALUE = character(1)
      )
      receptor <- vapply(strsplit(LR_pairs[x], split = "_", fixed = TRUE),
        utils::tail, 1,
        FUN.VALUE = character(1)
      )

      pos_lr <- match(c(ligand, receptor), rownames(gene_expr))
      # When a ligand or receptor is not found, NA value should be returned.
      by_patient <- t(as.data.frame(apply(gene_expr[pos_lr, ], 2, min)))
      rownames(by_patient) <- LR_pairs[x]
      return(by_patient)
    }
  ))
  LR_pairs_computed <- t(LR_pairs_computed)

  # Apply grouping to LRpairs data
  for (X in seq_len(length(group_lrpairs))) {
    keep <- unique(group_lrpairs[[X]]$main)
    remove <- unique(group_lrpairs[[X]]$involved_pairs)
    combo_name <- unique(group_lrpairs[[X]]$combo_name)

    pos_remove <- match(remove, colnames(LR_pairs_computed))
    pos_keep <- match(keep, colnames(LR_pairs_computed))

    colnames(LR_pairs_computed)[pos_keep] <- combo_name
    LR_pairs_computed <- LR_pairs_computed[, -pos_remove]
  }
  # Remove LR pairs with all NA values
  LR_pairs_computed <- LR_pairs_computed[, !is.na(apply(LR_pairs_computed, 2, sum))]

  if (verbose) message("Ligand-Receptor pair weights computed \n")
  return(as.data.frame(LR_pairs_computed))
}
