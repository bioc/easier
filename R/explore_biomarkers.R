#' Explore biomarkers of immune response
#'
#' Provides a good overview of the computed features
#' (biomarkers) including the corresponding weights from the
#' trained model. If \code{patient_response} is provided,
#' this function shows statistically significant biomarkers
#' between responders (R) and non-responders (NR) patients.
#'
#' @importFrom stats aggregate
#' @importFrom utils combn
#' @importFrom reshape2 melt
#' @importFrom rstatix wilcox_test wilcox_effsize
#' @importFrom coin pvalue
#' @importFrom ggrepel geom_text_repel
#' @import ggplot2
#' @importFrom ggpubr ggarrange annotate_figure text_grob
#' @importFrom easierData get_opt_models get_intercell_networks
#'
#' @param pathways numeric matrix with pathways activity
#' (rows = samples; columns = pathways). This is the
#' output from \code{compute_pathway_activity}.
#' @param immunecells numeric matrix with immune cell quantification
#' (rows = samples; columns = cell types). This is the
#' output from \code{compute_cell_fractions}.
#' @param tfs numeric matrix with transcription factors activity
#' (rows = samples; columns = transcription factors). This is the
#' output from \code{compute_TF_activity}.
#' @param lrpairs numeric matrix with ligand-receptor weights
#' (rows = samples; columns = ligand-receptor pairs). This is the
#' output from \code{compute_LR_pairs}.
#' @param ccpairs numeric matrix with cell-cell scores
#' (rows = samples; columns = cell-cell pairs). This is the
#' output from \code{compute_CC_pairs}.
#' @param cancer_type character string indicating which cancer-specific
#' model should be used to compute the predictions. This should be
#' available from the cancer-specific models. The following cancer types
#' have a corresponding model available: "BLCA", "BRCA", "CESC", "CRC",
#' "GBM", "HNSC", "KIRC", "KIRP", "LIHC", "LUAD", "LUSC", "NSCLC", "OV",
#' "PAAD", "PRAD", "SKCM", "STAD", "THCA" and "UCEC".
#' @param patient_label character vector with two factor levels,
#' e.g. NR (Non-responders) vs R (Responders), pre- vs on- treatment.
#' @param verbose logical flag indicating whether to display messages
#' about the process.
#'
#' @return \itemize{
#' \item{A combined plot for each type of quantitative descriptors,
#' showing the original distribution of the features and the importance
#' of these features for the trained models}
#' #' \item{Volcano plot displaying relevant biomarkers differentiating
#' responders vs non-responders patients.}
#' }
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
#' cancer_type <- metadata(dataset_mariathasan)[["cancertype"]]
#'
#' # Select a subset of patients to reduce vignette building time.
#' pat_subset <- c(
#'   "SAM76a431ba6ce1", "SAMd3bd67996035", "SAMd3601288319e",
#'   "SAMba1a34b5a060", "SAM18a4dabbc557"
#' )
#' RNA_tpm <- RNA_tpm[, colnames(RNA_tpm) %in% pat_subset]
#'
#' # Computation of TF activity
#' tf_activity <- compute_TF_activity(
#'   RNA_tpm = RNA_tpm
#' )
#'
#' # retrieve clinical response
#' patient_ICBresponse <- colData(dataset_mariathasan)[["BOR"]]
#' names(patient_ICBresponse) <- colData(dataset_mariathasan)[["pat_id"]]
#' patient_ICBresponse <- patient_ICBresponse[names(patient_ICBresponse) %in% pat_subset]
#'
#' # Investigate possible biomarkers
#' output_biomarkers <- explore_biomarkers(
#'   tfs = tf_activity,
#'   cancer_type = cancer_type,
#'   patient_label = patient_ICBresponse
#' )
#'
#' \donttest{
#'
#' RNA_counts <- assays(dataset_mariathasan)[["counts"]]
#' RNA_counts <- RNA_counts[, colnames(RNA_counts) %in% pat_subset]
#'
#' # Computation of cell fractions
#' cell_fractions <- compute_cell_fractions(RNA_tpm = RNA_tpm)
#'
#' # Computation of pathway scores
#' pathway_activity <- compute_pathway_activity(
#'   RNA_counts = RNA_counts,
#'   remove_sig_genes_immune_response = TRUE
#' )
#'
#' # Computation of ligand-receptor pair weights
#' lrpair_weights <- compute_LR_pairs(
#'   RNA_tpm = RNA_tpm,
#'   cancer_type = "pancan"
#' )
#'
#' # Computation of cell-cell interaction scores
#' ccpair_scores <- compute_CC_pairs(
#'   lrpairs = lrpair_weights,
#'   cancer_type = "pancan"
#' )
#'
#' # Investigate possible biomarkers
#' output_biomarkers <- explore_biomarkers(
#'   pathways = pathway_activity,
#'   immunecells = cell_fractions,
#'   lrpairs = lrpair_weights,
#'   tfs = tf_activity,
#'   ccpairs = ccpair_scores,
#'   cancer_type = cancer_type,
#'   patient_label = patient_ICBresponse
#' )
#' }
explore_biomarkers <- function(pathways = NULL,
                               immunecells = NULL,
                               tfs = NULL,
                               lrpairs = NULL,
                               ccpairs = NULL,
                               cancer_type,
                               patient_label = NULL,
                               verbose = TRUE) {
  if (missing(cancer_type)) stop("cancer type needs to be specified")

  available_cancer_types <- c(
    "BLCA", "BRCA", "CESC", "CRC", "GBM", "HNSC",
    "KIRC", "KIRP", "LIHC", "LUAD", "LUSC", "NSCLC",
    "OV", "PAAD", "PRAD", "SKCM", "STAD", "THCA",
    "UCEC"
  )

  if (!cancer_type %in% available_cancer_types) {
    stop("cancer-type specific model not available for this cancer type")
  }
  if (is.null(patient_label) == FALSE) {
    if (length(levels(as.factor(patient_label)) == 2) == FALSE) {
      stop("patient_label does not involve two factor levels")
    }
  }
  if (all(
    is.null(pathways), is.null(immunecells), is.null(tfs),
    is.null(lrpairs), is.null(ccpairs)
  )) {
    stop("none signature specified")
  }
  # Retrieve internal data
  opt_models <- suppressMessages(easierData::get_opt_models())
  intercell_networks <- suppressMessages(easierData::get_intercell_networks())
  # Initialize variables
  views <- c(
    pathways = "gaussian",
    immunecells = "gaussian",
    tfs = "gaussian",
    lrpairs = "gaussian",
    ccpairs = "gaussian"
  )
  # Check which views are missing
  miss_views <- c(
    ifelse(missing(pathways), NA, 1),
    ifelse(missing(immunecells), NA, 2),
    ifelse(missing(tfs), NA, 3),
    ifelse(missing(lrpairs), NA, 4),
    ifelse(missing(ccpairs), NA, 5)
  )
  # Single views
  view_simples <- lapply(miss_views[!is.na(miss_views)], function(X) {
    tmp <- views[X]
    return(tmp)
  })
  # All corresponding views
  view_combinations <- view_simples

  get_biomarkers_features <- function(view, cancer_type, patient_label, verbose = TRUE) {
    view_info <- view_combinations[[view]]
    view_name <- paste(names(view_info), collapse = "_")
    # if (verbose) message("Examining ", view_name, " biomarkers \n")
    # ---------- #
    # Features #
    # ---------- #
    features <- as.matrix(get(view_name))
    features_z <- calc_z_score(features)
    if (is.null(patient_label)) {
      patients <- rownames(features)
    } else {
      patients <- intersect(names(patient_label), rownames(features))
      # add response labels
      response <- patient_label[patients]
      response_df <- data.frame(sample = names(response), label = response)
    }
    features <- features[patients, ]
    features_z <- features_z[patients, ]
    features_df <- reshape2::melt(features)
    features_df_z <- reshape2::melt(features_z)
    features_df$value_z <- features_df_z$value
    names(features_df) <- c("sample", "feature", "value", "value_z")
    if (is.null(patient_label) == FALSE) {
      # Merge
      features_df <- merge(features_df, response_df)
    }
    features_df$datatype <- view_name
    # ---------- #
    # Weights #
    # ---------- #
    opt_model_cancer_view_spec <- opt_models[[cancer_type]][[view_name]]

    my_coefs <- reshape2::melt(opt_model_cancer_view_spec)
    names(my_coefs) <- c("feature", "run", "estimate", "task")
    my_coefs$datatype <- view_name
    # remove intercept
    my_coefs <- subset(my_coefs, !feature %in% "(Intercept)")
    # calculate median across runs and tasks
    my_coefs_median <- stats::aggregate(estimate ~ feature + datatype,
      FUN = "median", na.rm = TRUE, data = my_coefs
    )

    return(list(weights = my_coefs_median, features = features_df))
  }

  plot_list <- lapply(seq_len(length(view_combinations)), function(ii) {
    biomarkers_weights_features <- get_biomarkers_features(ii, cancer_type, patient_label)
    biomarkers_weights <- biomarkers_weights_features$weights
    biomarkers_weights$feature <- droplevels(biomarkers_weights$feature)

    # change names for cell-cell pairs
    if (unique(biomarkers_weights$datatype) == "ccpairs") {
      new_variables_cc <- c(
        "CD8", "M", "B", "DC", "Endo", "Mast", "Fib", "Adip",
        "CD4", "NK", "Neu", "Mono", "Cancer"
      )
      old_variables_cc <- c(
        "CD8+T-Cell", "Macrophages", "B-Cell", "DendriticCells", "Endothelialcells",
        "Mastcells", "Fibroblasts", "Adipocytes", "CD4+T-Cell", "NKcells",
        "Neutrophils", "Monocytes", "Cancercell"
      )
      tmp <- as.character(biomarkers_weights$feature)
      for (X in seq_len(length(new_variables_cc))) {
        tmp <- gsub(old_variables_cc[X], new_variables_cc[X], tmp, fixed = TRUE)
      }
      biomarkers_weights$feature <- tmp
    }
    colnames(biomarkers_weights) <- c("variable", "datatype", "weight")

    features <- biomarkers_weights_features$features
    features <- features[!is.na(features$value), ]
    features$feature <- droplevels(features$feature)

    if (unique(features$datatype) == "ccpairs") {
      tmp <- features$feature
      tmp_2 <- levels(features$feature)
      for (X in seq_len(length(new_variables_cc))) {
        tmp <- gsub(old_variables_cc[X], new_variables_cc[X], tmp, fixed = TRUE)
        tmp_2 <- gsub(old_variables_cc[X], new_variables_cc[X], tmp_2, fixed = TRUE)
      }
      features$feature <- factor(tmp, levels = tmp_2)
    }

    # Sort biomarkers by weight
    biomarkers_weights_sort <- biomarkers_weights[order(abs(biomarkers_weights$weight),
      decreasing = TRUE
    ), ]
    # Keep 15 top biomarkers for those descriptors with higher amount of features
    if (nrow(biomarkers_weights_sort) > 15) {
      biomarkers_weights_sort <- biomarkers_weights_sort[seq_len(15), ]
    }
    # Two TFs differ across dorothea versions (our model was built based on a previous version)
    while (all(biomarkers_weights_sort$variable %in% features$feature) == FALSE) {
      which_features_missing <- !biomarkers_weights_sort$variable %in% features$feature
      missing_features <- as.character(biomarkers_weights_sort$variable[which_features_missing])
      biomarkers_weights_sort <- biomarkers_weights[order(abs(biomarkers_weights$weight), decreasing = TRUE), ]
      biomarkers_weights_sort <- biomarkers_weights_sort[!biomarkers_weights_sort$variable %in% missing_features, ]

      if (nrow(biomarkers_weights_sort) > 15) {
        biomarkers_weights_sort <- biomarkers_weights_sort[seq_len(15), ]
      }
    }
    biomarkers_weights_sort <- as.data.frame(biomarkers_weights_sort)

    # weights
    biomarkers_weights_sort$variable <- factor(biomarkers_weights_sort$variable,
      levels = unique(biomarkers_weights_sort$variable)
    )

    biomarkers_weights_sort$cor <- sign(biomarkers_weights_sort$weight)
    biomarkers_weights_sort$cor <- gsub("-1", "-", biomarkers_weights_sort$cor, fixed = TRUE)
    biomarkers_weights_sort$cor <- gsub("1", "+", biomarkers_weights_sort$cor, fixed = TRUE)
    biomarkers_weights_sort$cor <- factor(biomarkers_weights_sort$cor,
      levels = unique(biomarkers_weights_sort$cor)
    )

    # BARPLOT #
    barplot <- ggplot2::ggplot(
      biomarkers_weights_sort,
      ggplot2::aes(
        x = .data$variable,
        y = abs(.data$weight),
        fill = .data$cor
      )
    ) +
      ggplot2::geom_bar(stat = "identity", color = "white") +
      ggplot2::scale_fill_manual(
        name = "Association sign",
        labels = c("+", "-", "0"),
        values = c("+" = "#4477AA", "-" = "#BB4444", "0" = "gray")
      ) +
      ggplot2::theme(panel.grid = ggplot2::element_blank()) +
      ggplot2::theme(
        axis.text.x = ggplot2::element_text(size = 12, color = "black"),
        axis.title.y = ggplot2::element_blank(),
        axis.title.x = ggplot2::element_text(size = 12, color = "black", face = "bold"),
        axis.text.y = ggplot2::element_text(size = 12, color = "black"),
        axis.ticks.x = ggplot2::element_line(size = 0.5, color = "black"),
        axis.ticks.y = ggplot2::element_line(size = 0.5, color = "black"),
        legend.position = "top", legend.direction = "horizontal",
        legend.box.background = ggplot2::element_rect(color = "black", size = 0.3),
        legend.box.margin = ggplot2::margin(0.5, 0.5, 0.5, 0.5),
        legend.text = ggplot2::element_text(size = 12),
        legend.title = ggplot2::element_text(size = 12, face = "bold", vjust = 0.5),
        panel.border = ggplot2::element_blank(),
        panel.background = ggplot2::element_blank(),
        plot.margin = ggplot2::unit(c(0, 0, 0.2, 0.2), "cm"),
        axis.line.y = ggplot2::element_line(colour = "black"),
        axis.line.x = ggplot2::element_line(colour = "black")
      ) +
      ggplot2::labs(y = "Biomarker weight") +
      ggplot2::coord_flip()

    if (length(unique(biomarkers_weights$feature)) > 30) {
      barplot <- barplot + ggplot2::theme(
        axis.text.y = ggplot2::element_text(size = 10, color = "black")
      )
    } else {
      barplot <- barplot + ggplot2::theme(
        axis.text.y = ggplot2::element_text(size = 12, color = "black")
      )
    }

    features_boxplot <- subset(features, feature %in% unique(biomarkers_weights_sort$variable))
    features_boxplot$feature <- factor(as.character(features_boxplot$feature),
      levels = unique(biomarkers_weights_sort$variable)
    )
    if (is.null(patient_label) == FALSE) {
      features_boxplot$label <- factor(features_boxplot$label)
    } else {
      features_boxplot$label <- as.factor("UNK")
    }

    # BOXPLOT #
    boxplot <- ggplot2::ggplot(
      features_boxplot,
      ggplot2::aes(
        x = .data$feature,
        y = .data$value_z,
        fill = .data$label,
        color = .data$label
      )
    ) +
      ggplot2::geom_boxplot(alpha = 0.8, outlier.shape = NA) +
      ggplot2::geom_point(
        position = ggplot2::position_jitterdodge(),
        size = 0.05
      ) +
      ggplot2::scale_fill_manual(
        name = "Label",
        labels = levels(features_boxplot$label),
        values = c("darkgrey", "black")
      ) +
      ggplot2::scale_color_manual(
        name = "Label",
        labels = levels(features_boxplot$label),
        values = c("darkgrey", "black")
      ) +
      ggplot2::ylim(c(-5, 5)) +
      ggplot2::theme_minimal() +
      ggplot2::theme(panel.grid = ggplot2::element_blank()) +
      ggplot2::theme(
        axis.text.x = ggplot2::element_text(
          size = 12, angle = 45,
          hjust = 1, color = "black"
        ),
        axis.text.y = ggplot2::element_blank(),
        axis.title.y = ggplot2::element_blank(),
        axis.title.x = ggplot2::element_text(size = 12, color = "black", face = "bold"),
        axis.ticks.x = ggplot2::element_line(size = 0.5, color = "black"),
        axis.ticks.y = ggplot2::element_blank(),
        legend.position = "top", legend.direction = "horizontal",
        legend.box.background = ggplot2::element_rect(color = "black", size = 0.3),
        legend.box.margin = ggplot2::margin(0.5, 0.5, 0.5, 0.5),
        legend.text = ggplot2::element_text(size = 12),
        legend.title = ggplot2::element_text(size = 12, face = "bold", vjust = 0.5),
        plot.margin = ggplot2::unit(c(0.2, 0, 0, 0.2), "cm"),
        axis.line.x = ggplot2::element_line(colour = "black"),
        axis.line.y = ggplot2::element_blank()
      ) +
      ggplot2::labs(y = "Z-score") +
      ggplot2::coord_flip()

    # Combine plots
    figure <- ggpubr::ggarrange(barplot, boxplot,
      common.legend = FALSE,
      ncol = 2, nrow = 1, heights = c(1, 1), align = "h"
    )

    figure <- ggpubr::annotate_figure(figure, top = ggpubr::text_grob(
      paste0(
        " Quantitative descriptor: ",
        unique(biomarkers_weights_sort$datatype)
      ),
      color = "black", face = "bold", size = 14
    ))

    plot_list <- print(figure)
    return(plot_list)
  })

  comparison <- do.call(rbind, lapply(seq_len(length(view_combinations)), function(ii) {
    biomarkers_weights_features <- get_biomarkers_features(ii, cancer_type, patient_label)
    biomarkers_weights <- biomarkers_weights_features$weights
    biomarkers_weights$feature <- droplevels(biomarkers_weights$feature)

    # change names for cell-cell pairs
    if (unique(biomarkers_weights$datatype) == "ccpairs") {
      new_variables_cc <- c(
        "CD8", "M", "B", "DC", "Endo", "Mast", "Fib", "Adip",
        "CD4", "NK", "Neu", "Mono", "Cancer"
      )
      old_variables_cc <- c(
        "CD8+T-Cell", "Macrophages", "B-Cell", "DendriticCells", "Endothelialcells",
        "Mastcells", "Fibroblasts", "Adipocytes", "CD4+T-Cell", "NKcells",
        "Neutrophils", "Monocytes", "Cancercell"
      )
      tmp <- as.character(biomarkers_weights$feature)
      for (X in seq_len(length(new_variables_cc))) {
        tmp <- gsub(old_variables_cc[X], new_variables_cc[X], tmp, fixed = TRUE)
      }
      biomarkers_weights$feature <- tmp
    }
    colnames(biomarkers_weights) <- c("variable", "datatype", "weight")

    features <- biomarkers_weights_features$features
    features <- features[!is.na(features$value), ]
    features$feature <- droplevels(features$feature)

    if (unique(features$datatype) == "ccpairs") {
      tmp <- features$feature
      tmp_2 <- levels(features$feature)
      for (X in seq_len(length(new_variables_cc))) {
        tmp <- gsub(old_variables_cc[X], new_variables_cc[X], tmp, fixed = TRUE)
        tmp_2 <- gsub(old_variables_cc[X], new_variables_cc[X], tmp_2, fixed = TRUE)
      }
      features$feature <- factor(tmp, levels = tmp_2)
    }

    # Sort biomarkers by weight
    biomarkers_weights_sort <- biomarkers_weights[order(abs(biomarkers_weights$weight),
                                                        decreasing = TRUE
    ), ]
    # Keep 15 top biomarkers for those descriptors with higher amount of features
    if (nrow(biomarkers_weights_sort) > 15) {
      biomarkers_weights_sort <- biomarkers_weights_sort[seq_len(15), ]
    }
    # Two TFs differ across dorothea versions (our model was built based on a previous version)
    while (all(biomarkers_weights_sort$variable %in% features$feature) == FALSE) {
      which_features_missing <- !biomarkers_weights_sort$variable %in% features$feature
      missing_features <- as.character(biomarkers_weights_sort$variable[which_features_missing])
      biomarkers_weights_sort <- biomarkers_weights[order(abs(biomarkers_weights$weight), decreasing = TRUE), ]
      biomarkers_weights_sort <- biomarkers_weights_sort[!biomarkers_weights_sort$variable %in% missing_features, ]

      if (nrow(biomarkers_weights_sort) > 15) {
        biomarkers_weights_sort <- biomarkers_weights_sort[seq_len(15), ]
      }
    }
    biomarkers_weights_sort <- as.data.frame(biomarkers_weights_sort)

    if (unique(features$datatype) == "ccpairs") {
      tmp <- features$feature
      tmp_2 <- levels(features$feature)
      for (X in seq_len(length(new_variables_cc))) {
        tmp <- gsub(old_variables_cc[X], new_variables_cc[X], tmp, fixed = TRUE)
        tmp_2 <- gsub(old_variables_cc[X], new_variables_cc[X], tmp_2, fixed = TRUE)
      }
      features$feature <- factor(tmp, levels = tmp_2)
    }

    features_names <- levels(features$feature)
    datatype_comparison <- do.call(rbind, lapply(features_names, function(x) {
      # consider only the data for that variable and separate R and NR
      tmp <- subset(features, feature == x)
      # compute average
      tmp_mean <- tapply(tmp$value, tmp$label, mean)
      if (length(unique(tmp$value)) != 1) {
        # compute wilcoxon sum rank test, effect size and sign
        stattest <- rstatix::wilcox_test(data = tmp, value ~ label)
        effsize <- rstatix::wilcox_effsize(data = tmp, value ~ label)
        sign <- sign(tmp_mean["R"] - tmp_mean["NR"])
        p_val <- stattest$p
        eff_size <- effsize$effsize
      } else {
        p_val <- 1
        eff_size <- 0
        sign <- 0
      }
      tmp_df <- data.frame(
        datatype = unique(features$datatype),
        variable = x,
        p_val = p_val,
        eff_size = eff_size,
        sign = sign
      )
      return(tmp_df)
    }))
    datatype_comparison <- merge(datatype_comparison, biomarkers_weights)
    datatype_comparison$istop <- FALSE
    datatype_comparison$istop[datatype_comparison$variable %in% biomarkers_weights_sort$variable] <- TRUE
    return(datatype_comparison)
  }))

  comparison$signedEffect <- comparison$eff_size * comparison$sign
  comparison$threshold <- as.numeric(as.factor(comparison$p_val <= 0.05))
  comparison$threshold <- factor(comparison$threshold,
    levels = c(1, 2),
    labels = c("notSign", "Sign")
  )

  # Add arrow in lrpairs and ccpairs
  if (any(comparison$datatype %in% c("lrpairs", "ccpairs"))) {
    select_datatype <- which(comparison$datatype %in% c("lrpairs", "ccpairs"))
    tmp <- vapply(strsplit(as.character(comparison$variable)[select_datatype],
      split = "_"
    ), function(X) {
      return(X[seq_len(8)])
    }, FUN.VALUE = character(8))

    # LR pairs network
    intercell_network <- intercell_networks[["pancan"]]
    LR_pairs <- unique(paste0(
      intercell_network$ligands, "_",
      intercell_network$receptors
    ))

    new_name <- do.call(c, lapply(seq_len(ncol(tmp)), function(X) {
      tmp_2 <- tmp[!(is.na(tmp[, X])), X]
      if (length(tmp_2) > 2) {
        pos_comb <- utils::combn(length(tmp_2), 2)
        search <- vapply(seq_len(ncol(pos_comb)), function(X) {
          paste(tmp_2[pos_comb[, X]], collapse = "_")
        }, FUN.VALUE = character(1))
        keep <- search[search %in% LR_pairs]
        maj <- names(which(table(unlist(strsplit(keep, split = "_"))) > 1))
        other <- paste(tmp_2[!tmp_2 %in% maj])

        if (match(maj, tmp_2) == length(tmp_2)) {
          new_name <- paste0(paste(other, collapse = "_"), "->", maj)
        } else {
          new_name <- paste0(maj, "->", paste(other, collapse = "_"))
        }
      } else if (length(tmp_2) <= 2) {
        new_name <- paste(tmp_2, collapse = "->")
      }
      return(new_name)
    }))
    comparison$variable[select_datatype] <- new_name
  }

  xminmax <- max(abs(comparison$signedEffect))
  xminmax <- xminmax + xminmax * 0.01
  ymax <- max(-log10(comparison$p_val))
  ymax <- ymax + ymax * 0.01

  volcano_plot <- ggplot2::ggplot(
    data = comparison,
    ggplot2::aes(
      x = .data$signedEffect,
      y = -log10(.data$p_val),
      color = .data$threshold,
      size = abs(.data$weight)
    )
  ) +
    ggplot2::geom_point(
      alpha = 1,
      ggplot2::aes(shape = as.factor(sign(weight)))
    ) +
    ggplot2::xlim(c(-xminmax, xminmax)) +
    ggplot2::ylim(c(0, ymax)) +
    ggplot2::xlab("higher in NR          effect size          higher in R") +
    ggplot2::ylab("-log10 p-value") +
    ggplot2::ggtitle("") +
    ggplot2::scale_color_manual(
      labels = levels(comparison$threshold),
      values = c("#a6a6a6", "#4BA8D7"),
      name = "R vs NR significance"
    ) +
    ggplot2::scale_shape_manual(values = c(15, 16, 17), name = "Association sign") +
    ggplot2::scale_size_continuous(name = "Estimated weight") +
    ggplot2::theme_bw() +
    ggplot2::geom_hline(yintercept = -log10(0.05), linetype = "longdash", colour = "#9e9e9e") +
    ggplot2::geom_vline(xintercept = 0, linetype = "solid", colour = "#9e9e9e") +
    ggplot2::theme(
      axis.text = ggplot2::element_text(color = "black"),
      axis.ticks = ggplot2::element_line(color = "black")
    ) +
    ggplot2::theme(legend.position = "right") +
    ggplot2::labs(title = paste0(" All quantitative descriptor at once"))

  if (length(unique(comparison$threshold)) == 2) {
    volcano_plot <- volcano_plot + ggrepel::geom_text_repel(
      data = subset(comparison, (threshold != "notSign")),
      ggplot2::aes(
        x = .data$signedEffect, y = -log10(.data$p_val),
        label = .data$variable, size = .05
      ),
      show.legend = NA, inherit.aes = FALSE, max.overlaps = 20
    )
  }

  plot_list[[length(view_combinations) + 1]] <- suppressWarnings(print(volcano_plot))
  return(plot_list)
}
