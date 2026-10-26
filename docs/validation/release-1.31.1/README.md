# Release 1.31.1 validation

This packaging patch restores the offline wiki omitted from the 1.31.0 standalone browser archive. The hosted wiki remained intact. The published 1.31.0 archive is the retained failing control; the new archive must contain all 13,819 committed wiki files with identical contents. The new validator is unit tested for omission, partial bundles and changed content.

All 446 compiled game scripts are unchanged across platforms and compared with 1.31.0. Pack resources and Windows engine code are compared separately; only version metadata and Godot-generated root-node IDs differ. The 628 final-package assertions from 1.31.0 remain applicable, with a fresh packaged startup/knife check, fresh browser start and real service-worker upgrade for 1.31.1. Native Windows OS, macOS and Android device runtime limitations remain unchanged.
