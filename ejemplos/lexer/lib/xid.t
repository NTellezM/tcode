// Generado por tests/generar_xid.py con Unicode 15.0.0. No editar a mano.
//
// Los caracteres no ASCII que pueden empezar (XID_Start) y seguir
// (XID_Continue) un nombre de Tcode, como una busqueda binaria.

fn xid_inicio(c: usize) -> bool {
    if c < 43697 {
        if c < 4256 {
            if c < 2749 {
                if c < 2048 {
                    if c < 1162 {
                        if c < 880 {
                            if c < 248 {
                                if c == 170 { return true; }
                                if c == 181 { return true; }
                                if c == 186 { return true; }
                                if c >= 192 && c <= 214 { return true; }
                                if c >= 216 && c <= 246 { return true; }
                                return false;
                            }
                            if c >= 248 && c <= 705 { return true; }
                            if c >= 710 && c <= 721 { return true; }
                            if c >= 736 && c <= 740 { return true; }
                            if c == 748 { return true; }
                            if c == 750 { return true; }
                            return false;
                        }
                        if c < 904 {
                            if c >= 880 && c <= 884 { return true; }
                            if c >= 886 && c <= 887 { return true; }
                            if c >= 891 && c <= 893 { return true; }
                            if c == 895 { return true; }
                            if c == 902 { return true; }
                            return false;
                        }
                        if c >= 904 && c <= 906 { return true; }
                        if c == 908 { return true; }
                        if c >= 910 && c <= 929 { return true; }
                        if c >= 931 && c <= 1013 { return true; }
                        if c >= 1015 && c <= 1153 { return true; }
                        return false;
                    }
                    if c < 1765 {
                        if c < 1519 {
                            if c >= 1162 && c <= 1327 { return true; }
                            if c >= 1329 && c <= 1366 { return true; }
                            if c == 1369 { return true; }
                            if c >= 1376 && c <= 1416 { return true; }
                            if c >= 1488 && c <= 1514 { return true; }
                            return false;
                        }
                        if c >= 1519 && c <= 1522 { return true; }
                        if c >= 1568 && c <= 1610 { return true; }
                        if c >= 1646 && c <= 1647 { return true; }
                        if c >= 1649 && c <= 1747 { return true; }
                        if c == 1749 { return true; }
                        return false;
                    }
                    if c < 1810 {
                        if c >= 1765 && c <= 1766 { return true; }
                        if c >= 1774 && c <= 1775 { return true; }
                        if c >= 1786 && c <= 1788 { return true; }
                        if c == 1791 { return true; }
                        if c == 1808 { return true; }
                        return false;
                    }
                    if c >= 1810 && c <= 1839 { return true; }
                    if c >= 1869 && c <= 1957 { return true; }
                    if c == 1969 { return true; }
                    if c >= 1994 && c <= 2026 { return true; }
                    if c >= 2036 && c <= 2037 { return true; }
                    if c == 2042 { return true; }
                    return false;
                }
                if c < 2510 {
                    if c < 2365 {
                        if c < 2144 {
                            if c >= 2048 && c <= 2069 { return true; }
                            if c == 2074 { return true; }
                            if c == 2084 { return true; }
                            if c == 2088 { return true; }
                            if c >= 2112 && c <= 2136 { return true; }
                            return false;
                        }
                        if c >= 2144 && c <= 2154 { return true; }
                        if c >= 2160 && c <= 2183 { return true; }
                        if c >= 2185 && c <= 2190 { return true; }
                        if c >= 2208 && c <= 2249 { return true; }
                        if c >= 2308 && c <= 2361 { return true; }
                        return false;
                    }
                    if c < 2447 {
                        if c == 2365 { return true; }
                        if c == 2384 { return true; }
                        if c >= 2392 && c <= 2401 { return true; }
                        if c >= 2417 && c <= 2432 { return true; }
                        if c >= 2437 && c <= 2444 { return true; }
                        return false;
                    }
                    if c >= 2447 && c <= 2448 { return true; }
                    if c >= 2451 && c <= 2472 { return true; }
                    if c >= 2474 && c <= 2480 { return true; }
                    if c == 2482 { return true; }
                    if c >= 2486 && c <= 2489 { return true; }
                    if c == 2493 { return true; }
                    return false;
                }
                if c < 2613 {
                    if c < 2565 {
                        if c == 2510 { return true; }
                        if c >= 2524 && c <= 2525 { return true; }
                        if c >= 2527 && c <= 2529 { return true; }
                        if c >= 2544 && c <= 2545 { return true; }
                        if c == 2556 { return true; }
                        return false;
                    }
                    if c >= 2565 && c <= 2570 { return true; }
                    if c >= 2575 && c <= 2576 { return true; }
                    if c >= 2579 && c <= 2600 { return true; }
                    if c >= 2602 && c <= 2608 { return true; }
                    if c >= 2610 && c <= 2611 { return true; }
                    return false;
                }
                if c < 2693 {
                    if c >= 2613 && c <= 2614 { return true; }
                    if c >= 2616 && c <= 2617 { return true; }
                    if c >= 2649 && c <= 2652 { return true; }
                    if c == 2654 { return true; }
                    if c >= 2674 && c <= 2676 { return true; }
                    return false;
                }
                if c >= 2693 && c <= 2701 { return true; }
                if c >= 2703 && c <= 2705 { return true; }
                if c >= 2707 && c <= 2728 { return true; }
                if c >= 2730 && c <= 2736 { return true; }
                if c >= 2738 && c <= 2739 { return true; }
                if c >= 2741 && c <= 2745 { return true; }
                return false;
            }
            if c < 3296 {
                if c < 2974 {
                    if c < 2877 {
                        if c < 2831 {
                            if c == 2749 { return true; }
                            if c == 2768 { return true; }
                            if c >= 2784 && c <= 2785 { return true; }
                            if c == 2809 { return true; }
                            if c >= 2821 && c <= 2828 { return true; }
                            return false;
                        }
                        if c >= 2831 && c <= 2832 { return true; }
                        if c >= 2835 && c <= 2856 { return true; }
                        if c >= 2858 && c <= 2864 { return true; }
                        if c >= 2866 && c <= 2867 { return true; }
                        if c >= 2869 && c <= 2873 { return true; }
                        return false;
                    }
                    if c < 2949 {
                        if c == 2877 { return true; }
                        if c >= 2908 && c <= 2909 { return true; }
                        if c >= 2911 && c <= 2913 { return true; }
                        if c == 2929 { return true; }
                        if c == 2947 { return true; }
                        return false;
                    }
                    if c >= 2949 && c <= 2954 { return true; }
                    if c >= 2958 && c <= 2960 { return true; }
                    if c >= 2962 && c <= 2965 { return true; }
                    if c >= 2969 && c <= 2970 { return true; }
                    if c == 2972 { return true; }
                    return false;
                }
                if c < 3160 {
                    if c < 3077 {
                        if c >= 2974 && c <= 2975 { return true; }
                        if c >= 2979 && c <= 2980 { return true; }
                        if c >= 2984 && c <= 2986 { return true; }
                        if c >= 2990 && c <= 3001 { return true; }
                        if c == 3024 { return true; }
                        return false;
                    }
                    if c >= 3077 && c <= 3084 { return true; }
                    if c >= 3086 && c <= 3088 { return true; }
                    if c >= 3090 && c <= 3112 { return true; }
                    if c >= 3114 && c <= 3129 { return true; }
                    if c == 3133 { return true; }
                    return false;
                }
                if c < 3214 {
                    if c >= 3160 && c <= 3162 { return true; }
                    if c == 3165 { return true; }
                    if c >= 3168 && c <= 3169 { return true; }
                    if c == 3200 { return true; }
                    if c >= 3205 && c <= 3212 { return true; }
                    return false;
                }
                if c >= 3214 && c <= 3216 { return true; }
                if c >= 3218 && c <= 3240 { return true; }
                if c >= 3242 && c <= 3251 { return true; }
                if c >= 3253 && c <= 3257 { return true; }
                if c == 3261 { return true; }
                if c >= 3293 && c <= 3294 { return true; }
                return false;
            }
            if c < 3724 {
                if c < 3461 {
                    if c < 3389 {
                        if c >= 3296 && c <= 3297 { return true; }
                        if c >= 3313 && c <= 3314 { return true; }
                        if c >= 3332 && c <= 3340 { return true; }
                        if c >= 3342 && c <= 3344 { return true; }
                        if c >= 3346 && c <= 3386 { return true; }
                        return false;
                    }
                    if c == 3389 { return true; }
                    if c == 3406 { return true; }
                    if c >= 3412 && c <= 3414 { return true; }
                    if c >= 3423 && c <= 3425 { return true; }
                    if c >= 3450 && c <= 3455 { return true; }
                    return false;
                }
                if c < 3585 {
                    if c >= 3461 && c <= 3478 { return true; }
                    if c >= 3482 && c <= 3505 { return true; }
                    if c >= 3507 && c <= 3515 { return true; }
                    if c == 3517 { return true; }
                    if c >= 3520 && c <= 3526 { return true; }
                    return false;
                }
                if c >= 3585 && c <= 3632 { return true; }
                if c == 3634 { return true; }
                if c >= 3648 && c <= 3654 { return true; }
                if c >= 3713 && c <= 3714 { return true; }
                if c == 3716 { return true; }
                if c >= 3718 && c <= 3722 { return true; }
                return false;
            }
            if c < 3913 {
                if c < 3776 {
                    if c >= 3724 && c <= 3747 { return true; }
                    if c == 3749 { return true; }
                    if c >= 3751 && c <= 3760 { return true; }
                    if c == 3762 { return true; }
                    if c == 3773 { return true; }
                    return false;
                }
                if c >= 3776 && c <= 3780 { return true; }
                if c == 3782 { return true; }
                if c >= 3804 && c <= 3807 { return true; }
                if c == 3840 { return true; }
                if c >= 3904 && c <= 3911 { return true; }
                return false;
            }
            if c < 4186 {
                if c >= 3913 && c <= 3948 { return true; }
                if c >= 3976 && c <= 3980 { return true; }
                if c >= 4096 && c <= 4138 { return true; }
                if c == 4159 { return true; }
                if c >= 4176 && c <= 4181 { return true; }
                return false;
            }
            if c >= 4186 && c <= 4189 { return true; }
            if c == 4193 { return true; }
            if c >= 4197 && c <= 4198 { return true; }
            if c >= 4206 && c <= 4208 { return true; }
            if c >= 4213 && c <= 4225 { return true; }
            if c == 4238 { return true; }
            return false;
        }
        if c < 8305 {
            if c < 6480 {
                if c < 4992 {
                    if c < 4746 {
                        if c < 4682 {
                            if c >= 4256 && c <= 4293 { return true; }
                            if c == 4295 { return true; }
                            if c == 4301 { return true; }
                            if c >= 4304 && c <= 4346 { return true; }
                            if c >= 4348 && c <= 4680 { return true; }
                            return false;
                        }
                        if c >= 4682 && c <= 4685 { return true; }
                        if c >= 4688 && c <= 4694 { return true; }
                        if c == 4696 { return true; }
                        if c >= 4698 && c <= 4701 { return true; }
                        if c >= 4704 && c <= 4744 { return true; }
                        return false;
                    }
                    if c < 4802 {
                        if c >= 4746 && c <= 4749 { return true; }
                        if c >= 4752 && c <= 4784 { return true; }
                        if c >= 4786 && c <= 4789 { return true; }
                        if c >= 4792 && c <= 4798 { return true; }
                        if c == 4800 { return true; }
                        return false;
                    }
                    if c >= 4802 && c <= 4805 { return true; }
                    if c >= 4808 && c <= 4822 { return true; }
                    if c >= 4824 && c <= 4880 { return true; }
                    if c >= 4882 && c <= 4885 { return true; }
                    if c >= 4888 && c <= 4954 { return true; }
                    return false;
                }
                if c < 5952 {
                    if c < 5761 {
                        if c >= 4992 && c <= 5007 { return true; }
                        if c >= 5024 && c <= 5109 { return true; }
                        if c >= 5112 && c <= 5117 { return true; }
                        if c >= 5121 && c <= 5740 { return true; }
                        if c >= 5743 && c <= 5759 { return true; }
                        return false;
                    }
                    if c >= 5761 && c <= 5786 { return true; }
                    if c >= 5792 && c <= 5866 { return true; }
                    if c >= 5870 && c <= 5880 { return true; }
                    if c >= 5888 && c <= 5905 { return true; }
                    if c >= 5919 && c <= 5937 { return true; }
                    return false;
                }
                if c < 6108 {
                    if c >= 5952 && c <= 5969 { return true; }
                    if c >= 5984 && c <= 5996 { return true; }
                    if c >= 5998 && c <= 6000 { return true; }
                    if c >= 6016 && c <= 6067 { return true; }
                    if c == 6103 { return true; }
                    return false;
                }
                if c == 6108 { return true; }
                if c >= 6176 && c <= 6264 { return true; }
                if c >= 6272 && c <= 6312 { return true; }
                if c == 6314 { return true; }
                if c >= 6320 && c <= 6389 { return true; }
                if c >= 6400 && c <= 6430 { return true; }
                return false;
            }
            if c < 7418 {
                if c < 7086 {
                    if c < 6688 {
                        if c >= 6480 && c <= 6509 { return true; }
                        if c >= 6512 && c <= 6516 { return true; }
                        if c >= 6528 && c <= 6571 { return true; }
                        if c >= 6576 && c <= 6601 { return true; }
                        if c >= 6656 && c <= 6678 { return true; }
                        return false;
                    }
                    if c >= 6688 && c <= 6740 { return true; }
                    if c == 6823 { return true; }
                    if c >= 6917 && c <= 6963 { return true; }
                    if c >= 6981 && c <= 6988 { return true; }
                    if c >= 7043 && c <= 7072 { return true; }
                    return false;
                }
                if c < 7296 {
                    if c >= 7086 && c <= 7087 { return true; }
                    if c >= 7098 && c <= 7141 { return true; }
                    if c >= 7168 && c <= 7203 { return true; }
                    if c >= 7245 && c <= 7247 { return true; }
                    if c >= 7258 && c <= 7293 { return true; }
                    return false;
                }
                if c >= 7296 && c <= 7304 { return true; }
                if c >= 7312 && c <= 7354 { return true; }
                if c >= 7357 && c <= 7359 { return true; }
                if c >= 7401 && c <= 7404 { return true; }
                if c >= 7406 && c <= 7411 { return true; }
                if c >= 7413 && c <= 7414 { return true; }
                return false;
            }
            if c < 8031 {
                if c < 8008 {
                    if c == 7418 { return true; }
                    if c >= 7424 && c <= 7615 { return true; }
                    if c >= 7680 && c <= 7957 { return true; }
                    if c >= 7960 && c <= 7965 { return true; }
                    if c >= 7968 && c <= 8005 { return true; }
                    return false;
                }
                if c >= 8008 && c <= 8013 { return true; }
                if c >= 8016 && c <= 8023 { return true; }
                if c == 8025 { return true; }
                if c == 8027 { return true; }
                if c == 8029 { return true; }
                return false;
            }
            if c < 8134 {
                if c >= 8031 && c <= 8061 { return true; }
                if c >= 8064 && c <= 8116 { return true; }
                if c >= 8118 && c <= 8124 { return true; }
                if c == 8126 { return true; }
                if c >= 8130 && c <= 8132 { return true; }
                return false;
            }
            if c >= 8134 && c <= 8140 { return true; }
            if c >= 8144 && c <= 8147 { return true; }
            if c >= 8150 && c <= 8155 { return true; }
            if c >= 8160 && c <= 8172 { return true; }
            if c >= 8178 && c <= 8180 { return true; }
            if c >= 8182 && c <= 8188 { return true; }
            return false;
        }
        if c < 12549 {
            if c < 11559 {
                if c < 8488 {
                    if c < 8458 {
                        if c == 8305 { return true; }
                        if c == 8319 { return true; }
                        if c >= 8336 && c <= 8348 { return true; }
                        if c == 8450 { return true; }
                        if c == 8455 { return true; }
                        return false;
                    }
                    if c >= 8458 && c <= 8467 { return true; }
                    if c == 8469 { return true; }
                    if c >= 8472 && c <= 8477 { return true; }
                    if c == 8484 { return true; }
                    if c == 8486 { return true; }
                    return false;
                }
                if c < 8544 {
                    if c == 8488 { return true; }
                    if c >= 8490 && c <= 8505 { return true; }
                    if c >= 8508 && c <= 8511 { return true; }
                    if c >= 8517 && c <= 8521 { return true; }
                    if c == 8526 { return true; }
                    return false;
                }
                if c >= 8544 && c <= 8584 { return true; }
                if c >= 11264 && c <= 11492 { return true; }
                if c >= 11499 && c <= 11502 { return true; }
                if c >= 11506 && c <= 11507 { return true; }
                if c >= 11520 && c <= 11557 { return true; }
                return false;
            }
            if c < 11720 {
                if c < 11680 {
                    if c == 11559 { return true; }
                    if c == 11565 { return true; }
                    if c >= 11568 && c <= 11623 { return true; }
                    if c == 11631 { return true; }
                    if c >= 11648 && c <= 11670 { return true; }
                    return false;
                }
                if c >= 11680 && c <= 11686 { return true; }
                if c >= 11688 && c <= 11694 { return true; }
                if c >= 11696 && c <= 11702 { return true; }
                if c >= 11704 && c <= 11710 { return true; }
                if c >= 11712 && c <= 11718 { return true; }
                return false;
            }
            if c < 12337 {
                if c >= 11720 && c <= 11726 { return true; }
                if c >= 11728 && c <= 11734 { return true; }
                if c >= 11736 && c <= 11742 { return true; }
                if c >= 12293 && c <= 12295 { return true; }
                if c >= 12321 && c <= 12329 { return true; }
                return false;
            }
            if c >= 12337 && c <= 12341 { return true; }
            if c >= 12344 && c <= 12348 { return true; }
            if c >= 12353 && c <= 12438 { return true; }
            if c >= 12445 && c <= 12447 { return true; }
            if c >= 12449 && c <= 12538 { return true; }
            if c >= 12540 && c <= 12543 { return true; }
            return false;
        }
        if c < 43015 {
            if c < 42560 {
                if c < 19968 {
                    if c >= 12549 && c <= 12591 { return true; }
                    if c >= 12593 && c <= 12686 { return true; }
                    if c >= 12704 && c <= 12735 { return true; }
                    if c >= 12784 && c <= 12799 { return true; }
                    if c >= 13312 && c <= 19903 { return true; }
                    return false;
                }
                if c >= 19968 && c <= 42124 { return true; }
                if c >= 42192 && c <= 42237 { return true; }
                if c >= 42240 && c <= 42508 { return true; }
                if c >= 42512 && c <= 42527 { return true; }
                if c >= 42538 && c <= 42539 { return true; }
                return false;
            }
            if c < 42891 {
                if c >= 42560 && c <= 42606 { return true; }
                if c >= 42623 && c <= 42653 { return true; }
                if c >= 42656 && c <= 42735 { return true; }
                if c >= 42775 && c <= 42783 { return true; }
                if c >= 42786 && c <= 42888 { return true; }
                return false;
            }
            if c >= 42891 && c <= 42954 { return true; }
            if c >= 42960 && c <= 42961 { return true; }
            if c == 42963 { return true; }
            if c >= 42965 && c <= 42969 { return true; }
            if c >= 42994 && c <= 43009 { return true; }
            if c >= 43011 && c <= 43013 { return true; }
            return false;
        }
        if c < 43396 {
            if c < 43259 {
                if c >= 43015 && c <= 43018 { return true; }
                if c >= 43020 && c <= 43042 { return true; }
                if c >= 43072 && c <= 43123 { return true; }
                if c >= 43138 && c <= 43187 { return true; }
                if c >= 43250 && c <= 43255 { return true; }
                return false;
            }
            if c == 43259 { return true; }
            if c >= 43261 && c <= 43262 { return true; }
            if c >= 43274 && c <= 43301 { return true; }
            if c >= 43312 && c <= 43334 { return true; }
            if c >= 43360 && c <= 43388 { return true; }
            return false;
        }
        if c < 43520 {
            if c >= 43396 && c <= 43442 { return true; }
            if c == 43471 { return true; }
            if c >= 43488 && c <= 43492 { return true; }
            if c >= 43494 && c <= 43503 { return true; }
            if c >= 43514 && c <= 43518 { return true; }
            return false;
        }
        if c >= 43520 && c <= 43560 { return true; }
        if c >= 43584 && c <= 43586 { return true; }
        if c >= 43588 && c <= 43595 { return true; }
        if c >= 43616 && c <= 43638 { return true; }
        if c == 43642 { return true; }
        if c >= 43646 && c <= 43695 { return true; }
        return false;
    }
    if c < 71236 {
        if c < 67424 {
            if c < 65149 {
                if c < 64112 {
                    if c < 43793 {
                        if c < 43739 {
                            if c == 43697 { return true; }
                            if c >= 43701 && c <= 43702 { return true; }
                            if c >= 43705 && c <= 43709 { return true; }
                            if c == 43712 { return true; }
                            if c == 43714 { return true; }
                            return false;
                        }
                        if c >= 43739 && c <= 43741 { return true; }
                        if c >= 43744 && c <= 43754 { return true; }
                        if c >= 43762 && c <= 43764 { return true; }
                        if c >= 43777 && c <= 43782 { return true; }
                        if c >= 43785 && c <= 43790 { return true; }
                        return false;
                    }
                    if c < 43888 {
                        if c >= 43793 && c <= 43798 { return true; }
                        if c >= 43808 && c <= 43814 { return true; }
                        if c >= 43816 && c <= 43822 { return true; }
                        if c >= 43824 && c <= 43866 { return true; }
                        if c >= 43868 && c <= 43881 { return true; }
                        return false;
                    }
                    if c >= 43888 && c <= 44002 { return true; }
                    if c >= 44032 && c <= 55203 { return true; }
                    if c >= 55216 && c <= 55238 { return true; }
                    if c >= 55243 && c <= 55291 { return true; }
                    if c >= 63744 && c <= 64109 { return true; }
                    return false;
                }
                if c < 64326 {
                    if c < 64298 {
                        if c >= 64112 && c <= 64217 { return true; }
                        if c >= 64256 && c <= 64262 { return true; }
                        if c >= 64275 && c <= 64279 { return true; }
                        if c == 64285 { return true; }
                        if c >= 64287 && c <= 64296 { return true; }
                        return false;
                    }
                    if c >= 64298 && c <= 64310 { return true; }
                    if c >= 64312 && c <= 64316 { return true; }
                    if c == 64318 { return true; }
                    if c >= 64320 && c <= 64321 { return true; }
                    if c >= 64323 && c <= 64324 { return true; }
                    return false;
                }
                if c < 65008 {
                    if c >= 64326 && c <= 64433 { return true; }
                    if c >= 64467 && c <= 64605 { return true; }
                    if c >= 64612 && c <= 64829 { return true; }
                    if c >= 64848 && c <= 64911 { return true; }
                    if c >= 64914 && c <= 64967 { return true; }
                    return false;
                }
                if c >= 65008 && c <= 65017 { return true; }
                if c == 65137 { return true; }
                if c == 65139 { return true; }
                if c == 65143 { return true; }
                if c == 65145 { return true; }
                if c == 65147 { return true; }
                return false;
            }
            if c < 66349 {
                if c < 65536 {
                    if c < 65440 {
                        if c == 65149 { return true; }
                        if c >= 65151 && c <= 65276 { return true; }
                        if c >= 65313 && c <= 65338 { return true; }
                        if c >= 65345 && c <= 65370 { return true; }
                        if c >= 65382 && c <= 65437 { return true; }
                        return false;
                    }
                    if c >= 65440 && c <= 65470 { return true; }
                    if c >= 65474 && c <= 65479 { return true; }
                    if c >= 65482 && c <= 65487 { return true; }
                    if c >= 65490 && c <= 65495 { return true; }
                    if c >= 65498 && c <= 65500 { return true; }
                    return false;
                }
                if c < 65616 {
                    if c >= 65536 && c <= 65547 { return true; }
                    if c >= 65549 && c <= 65574 { return true; }
                    if c >= 65576 && c <= 65594 { return true; }
                    if c >= 65596 && c <= 65597 { return true; }
                    if c >= 65599 && c <= 65613 { return true; }
                    return false;
                }
                if c >= 65616 && c <= 65629 { return true; }
                if c >= 65664 && c <= 65786 { return true; }
                if c >= 65856 && c <= 65908 { return true; }
                if c >= 66176 && c <= 66204 { return true; }
                if c >= 66208 && c <= 66256 { return true; }
                if c >= 66304 && c <= 66335 { return true; }
                return false;
            }
            if c < 66864 {
                if c < 66513 {
                    if c >= 66349 && c <= 66378 { return true; }
                    if c >= 66384 && c <= 66421 { return true; }
                    if c >= 66432 && c <= 66461 { return true; }
                    if c >= 66464 && c <= 66499 { return true; }
                    if c >= 66504 && c <= 66511 { return true; }
                    return false;
                }
                if c >= 66513 && c <= 66517 { return true; }
                if c >= 66560 && c <= 66717 { return true; }
                if c >= 66736 && c <= 66771 { return true; }
                if c >= 66776 && c <= 66811 { return true; }
                if c >= 66816 && c <= 66855 { return true; }
                return false;
            }
            if c < 66967 {
                if c >= 66864 && c <= 66915 { return true; }
                if c >= 66928 && c <= 66938 { return true; }
                if c >= 66940 && c <= 66954 { return true; }
                if c >= 66956 && c <= 66962 { return true; }
                if c >= 66964 && c <= 66965 { return true; }
                return false;
            }
            if c >= 66967 && c <= 66977 { return true; }
            if c >= 66979 && c <= 66993 { return true; }
            if c >= 66995 && c <= 67001 { return true; }
            if c >= 67003 && c <= 67004 { return true; }
            if c >= 67072 && c <= 67382 { return true; }
            if c >= 67392 && c <= 67413 { return true; }
            return false;
        }
        if c < 69600 {
            if c < 68117 {
                if c < 67680 {
                    if c < 67592 {
                        if c >= 67424 && c <= 67431 { return true; }
                        if c >= 67456 && c <= 67461 { return true; }
                        if c >= 67463 && c <= 67504 { return true; }
                        if c >= 67506 && c <= 67514 { return true; }
                        if c >= 67584 && c <= 67589 { return true; }
                        return false;
                    }
                    if c == 67592 { return true; }
                    if c >= 67594 && c <= 67637 { return true; }
                    if c >= 67639 && c <= 67640 { return true; }
                    if c == 67644 { return true; }
                    if c >= 67647 && c <= 67669 { return true; }
                    return false;
                }
                if c < 67872 {
                    if c >= 67680 && c <= 67702 { return true; }
                    if c >= 67712 && c <= 67742 { return true; }
                    if c >= 67808 && c <= 67826 { return true; }
                    if c >= 67828 && c <= 67829 { return true; }
                    if c >= 67840 && c <= 67861 { return true; }
                    return false;
                }
                if c >= 67872 && c <= 67897 { return true; }
                if c >= 67968 && c <= 68023 { return true; }
                if c >= 68030 && c <= 68031 { return true; }
                if c == 68096 { return true; }
                if c >= 68112 && c <= 68115 { return true; }
                return false;
            }
            if c < 68608 {
                if c < 68297 {
                    if c >= 68117 && c <= 68119 { return true; }
                    if c >= 68121 && c <= 68149 { return true; }
                    if c >= 68192 && c <= 68220 { return true; }
                    if c >= 68224 && c <= 68252 { return true; }
                    if c >= 68288 && c <= 68295 { return true; }
                    return false;
                }
                if c >= 68297 && c <= 68324 { return true; }
                if c >= 68352 && c <= 68405 { return true; }
                if c >= 68416 && c <= 68437 { return true; }
                if c >= 68448 && c <= 68466 { return true; }
                if c >= 68480 && c <= 68497 { return true; }
                return false;
            }
            if c < 69296 {
                if c >= 68608 && c <= 68680 { return true; }
                if c >= 68736 && c <= 68786 { return true; }
                if c >= 68800 && c <= 68850 { return true; }
                if c >= 68864 && c <= 68899 { return true; }
                if c >= 69248 && c <= 69289 { return true; }
                return false;
            }
            if c >= 69296 && c <= 69297 { return true; }
            if c >= 69376 && c <= 69404 { return true; }
            if c == 69415 { return true; }
            if c >= 69424 && c <= 69445 { return true; }
            if c >= 69488 && c <= 69505 { return true; }
            if c >= 69552 && c <= 69572 { return true; }
            return false;
        }
        if c < 70287 {
            if c < 70006 {
                if c < 69840 {
                    if c >= 69600 && c <= 69622 { return true; }
                    if c >= 69635 && c <= 69687 { return true; }
                    if c >= 69745 && c <= 69746 { return true; }
                    if c == 69749 { return true; }
                    if c >= 69763 && c <= 69807 { return true; }
                    return false;
                }
                if c >= 69840 && c <= 69864 { return true; }
                if c >= 69891 && c <= 69926 { return true; }
                if c == 69956 { return true; }
                if c == 69959 { return true; }
                if c >= 69968 && c <= 70002 { return true; }
                return false;
            }
            if c < 70144 {
                if c == 70006 { return true; }
                if c >= 70019 && c <= 70066 { return true; }
                if c >= 70081 && c <= 70084 { return true; }
                if c == 70106 { return true; }
                if c == 70108 { return true; }
                return false;
            }
            if c >= 70144 && c <= 70161 { return true; }
            if c >= 70163 && c <= 70187 { return true; }
            if c >= 70207 && c <= 70208 { return true; }
            if c >= 70272 && c <= 70278 { return true; }
            if c == 70280 { return true; }
            if c >= 70282 && c <= 70285 { return true; }
            return false;
        }
        if c < 70480 {
            if c < 70419 {
                if c >= 70287 && c <= 70301 { return true; }
                if c >= 70303 && c <= 70312 { return true; }
                if c >= 70320 && c <= 70366 { return true; }
                if c >= 70405 && c <= 70412 { return true; }
                if c >= 70415 && c <= 70416 { return true; }
                return false;
            }
            if c >= 70419 && c <= 70440 { return true; }
            if c >= 70442 && c <= 70448 { return true; }
            if c >= 70450 && c <= 70451 { return true; }
            if c >= 70453 && c <= 70457 { return true; }
            if c == 70461 { return true; }
            return false;
        }
        if c < 70784 {
            if c == 70480 { return true; }
            if c >= 70493 && c <= 70497 { return true; }
            if c >= 70656 && c <= 70708 { return true; }
            if c >= 70727 && c <= 70730 { return true; }
            if c >= 70751 && c <= 70753 { return true; }
            return false;
        }
        if c >= 70784 && c <= 70831 { return true; }
        if c >= 70852 && c <= 70853 { return true; }
        if c == 70855 { return true; }
        if c >= 71040 && c <= 71086 { return true; }
        if c >= 71128 && c <= 71131 { return true; }
        if c >= 71168 && c <= 71215 { return true; }
        return false;
    }
    if c < 119973 {
        if c < 73648 {
            if c < 72250 {
                if c < 71957 {
                    if c < 71680 {
                        if c == 71236 { return true; }
                        if c >= 71296 && c <= 71338 { return true; }
                        if c == 71352 { return true; }
                        if c >= 71424 && c <= 71450 { return true; }
                        if c >= 71488 && c <= 71494 { return true; }
                        return false;
                    }
                    if c >= 71680 && c <= 71723 { return true; }
                    if c >= 71840 && c <= 71903 { return true; }
                    if c >= 71935 && c <= 71942 { return true; }
                    if c == 71945 { return true; }
                    if c >= 71948 && c <= 71955 { return true; }
                    return false;
                }
                if c < 72106 {
                    if c >= 71957 && c <= 71958 { return true; }
                    if c >= 71960 && c <= 71983 { return true; }
                    if c == 71999 { return true; }
                    if c == 72001 { return true; }
                    if c >= 72096 && c <= 72103 { return true; }
                    return false;
                }
                if c >= 72106 && c <= 72144 { return true; }
                if c == 72161 { return true; }
                if c == 72163 { return true; }
                if c == 72192 { return true; }
                if c >= 72203 && c <= 72242 { return true; }
                return false;
            }
            if c < 72968 {
                if c < 72704 {
                    if c == 72250 { return true; }
                    if c == 72272 { return true; }
                    if c >= 72284 && c <= 72329 { return true; }
                    if c == 72349 { return true; }
                    if c >= 72368 && c <= 72440 { return true; }
                    return false;
                }
                if c >= 72704 && c <= 72712 { return true; }
                if c >= 72714 && c <= 72750 { return true; }
                if c == 72768 { return true; }
                if c >= 72818 && c <= 72847 { return true; }
                if c >= 72960 && c <= 72966 { return true; }
                return false;
            }
            if c < 73066 {
                if c >= 72968 && c <= 72969 { return true; }
                if c >= 72971 && c <= 73008 { return true; }
                if c == 73030 { return true; }
                if c >= 73056 && c <= 73061 { return true; }
                if c >= 73063 && c <= 73064 { return true; }
                return false;
            }
            if c >= 73066 && c <= 73097 { return true; }
            if c == 73112 { return true; }
            if c >= 73440 && c <= 73458 { return true; }
            if c == 73474 { return true; }
            if c >= 73476 && c <= 73488 { return true; }
            if c >= 73490 && c <= 73523 { return true; }
            return false;
        }
        if c < 94179 {
            if c < 92784 {
                if c < 77824 {
                    if c == 73648 { return true; }
                    if c >= 73728 && c <= 74649 { return true; }
                    if c >= 74752 && c <= 74862 { return true; }
                    if c >= 74880 && c <= 75075 { return true; }
                    if c >= 77712 && c <= 77808 { return true; }
                    return false;
                }
                if c >= 77824 && c <= 78895 { return true; }
                if c >= 78913 && c <= 78918 { return true; }
                if c >= 82944 && c <= 83526 { return true; }
                if c >= 92160 && c <= 92728 { return true; }
                if c >= 92736 && c <= 92766 { return true; }
                return false;
            }
            if c < 93053 {
                if c >= 92784 && c <= 92862 { return true; }
                if c >= 92880 && c <= 92909 { return true; }
                if c >= 92928 && c <= 92975 { return true; }
                if c >= 92992 && c <= 92995 { return true; }
                if c >= 93027 && c <= 93047 { return true; }
                return false;
            }
            if c >= 93053 && c <= 93071 { return true; }
            if c >= 93760 && c <= 93823 { return true; }
            if c >= 93952 && c <= 94026 { return true; }
            if c == 94032 { return true; }
            if c >= 94099 && c <= 94111 { return true; }
            if c >= 94176 && c <= 94177 { return true; }
            return false;
        }
        if c < 110933 {
            if c < 110581 {
                if c == 94179 { return true; }
                if c >= 94208 && c <= 100343 { return true; }
                if c >= 100352 && c <= 101589 { return true; }
                if c >= 101632 && c <= 101640 { return true; }
                if c >= 110576 && c <= 110579 { return true; }
                return false;
            }
            if c >= 110581 && c <= 110587 { return true; }
            if c >= 110589 && c <= 110590 { return true; }
            if c >= 110592 && c <= 110882 { return true; }
            if c == 110898 { return true; }
            if c >= 110928 && c <= 110930 { return true; }
            return false;
        }
        if c < 113792 {
            if c == 110933 { return true; }
            if c >= 110948 && c <= 110951 { return true; }
            if c >= 110960 && c <= 111355 { return true; }
            if c >= 113664 && c <= 113770 { return true; }
            if c >= 113776 && c <= 113788 { return true; }
            return false;
        }
        if c >= 113792 && c <= 113800 { return true; }
        if c >= 113808 && c <= 113817 { return true; }
        if c >= 119808 && c <= 119892 { return true; }
        if c >= 119894 && c <= 119964 { return true; }
        if c >= 119966 && c <= 119967 { return true; }
        if c == 119970 { return true; }
        return false;
    }
    if c < 125259 {
        if c < 120630 {
            if c < 120123 {
                if c < 120005 {
                    if c >= 119973 && c <= 119974 { return true; }
                    if c >= 119977 && c <= 119980 { return true; }
                    if c >= 119982 && c <= 119993 { return true; }
                    if c == 119995 { return true; }
                    if c >= 119997 && c <= 120003 { return true; }
                    return false;
                }
                if c >= 120005 && c <= 120069 { return true; }
                if c >= 120071 && c <= 120074 { return true; }
                if c >= 120077 && c <= 120084 { return true; }
                if c >= 120086 && c <= 120092 { return true; }
                if c >= 120094 && c <= 120121 { return true; }
                return false;
            }
            if c < 120488 {
                if c >= 120123 && c <= 120126 { return true; }
                if c >= 120128 && c <= 120132 { return true; }
                if c == 120134 { return true; }
                if c >= 120138 && c <= 120144 { return true; }
                if c >= 120146 && c <= 120485 { return true; }
                return false;
            }
            if c >= 120488 && c <= 120512 { return true; }
            if c >= 120514 && c <= 120538 { return true; }
            if c >= 120540 && c <= 120570 { return true; }
            if c >= 120572 && c <= 120596 { return true; }
            if c >= 120598 && c <= 120628 { return true; }
            return false;
        }
        if c < 123191 {
            if c < 120772 {
                if c >= 120630 && c <= 120654 { return true; }
                if c >= 120656 && c <= 120686 { return true; }
                if c >= 120688 && c <= 120712 { return true; }
                if c >= 120714 && c <= 120744 { return true; }
                if c >= 120746 && c <= 120770 { return true; }
                return false;
            }
            if c >= 120772 && c <= 120779 { return true; }
            if c >= 122624 && c <= 122654 { return true; }
            if c >= 122661 && c <= 122666 { return true; }
            if c >= 122928 && c <= 122989 { return true; }
            if c >= 123136 && c <= 123180 { return true; }
            return false;
        }
        if c < 124896 {
            if c >= 123191 && c <= 123197 { return true; }
            if c == 123214 { return true; }
            if c >= 123536 && c <= 123565 { return true; }
            if c >= 123584 && c <= 123627 { return true; }
            if c >= 124112 && c <= 124139 { return true; }
            return false;
        }
        if c >= 124896 && c <= 124902 { return true; }
        if c >= 124904 && c <= 124907 { return true; }
        if c >= 124909 && c <= 124910 { return true; }
        if c >= 124912 && c <= 124926 { return true; }
        if c >= 124928 && c <= 125124 { return true; }
        if c >= 125184 && c <= 125251 { return true; }
        return false;
    }
    if c < 126559 {
        if c < 126530 {
            if c < 126503 {
                if c == 125259 { return true; }
                if c >= 126464 && c <= 126467 { return true; }
                if c >= 126469 && c <= 126495 { return true; }
                if c >= 126497 && c <= 126498 { return true; }
                if c == 126500 { return true; }
                return false;
            }
            if c == 126503 { return true; }
            if c >= 126505 && c <= 126514 { return true; }
            if c >= 126516 && c <= 126519 { return true; }
            if c == 126521 { return true; }
            if c == 126523 { return true; }
            return false;
        }
        if c < 126545 {
            if c == 126530 { return true; }
            if c == 126535 { return true; }
            if c == 126537 { return true; }
            if c == 126539 { return true; }
            if c >= 126541 && c <= 126543 { return true; }
            return false;
        }
        if c >= 126545 && c <= 126546 { return true; }
        if c == 126548 { return true; }
        if c == 126551 { return true; }
        if c == 126553 { return true; }
        if c == 126555 { return true; }
        if c == 126557 { return true; }
        return false;
    }
    if c < 126625 {
        if c < 126580 {
            if c == 126559 { return true; }
            if c >= 126561 && c <= 126562 { return true; }
            if c == 126564 { return true; }
            if c >= 126567 && c <= 126570 { return true; }
            if c >= 126572 && c <= 126578 { return true; }
            return false;
        }
        if c >= 126580 && c <= 126583 { return true; }
        if c >= 126585 && c <= 126588 { return true; }
        if c == 126590 { return true; }
        if c >= 126592 && c <= 126601 { return true; }
        if c >= 126603 && c <= 126619 { return true; }
        return false;
    }
    if c < 177984 {
        if c >= 126625 && c <= 126627 { return true; }
        if c >= 126629 && c <= 126633 { return true; }
        if c >= 126635 && c <= 126651 { return true; }
        if c >= 131072 && c <= 173791 { return true; }
        if c >= 173824 && c <= 177977 { return true; }
        return false;
    }
    if c >= 177984 && c <= 178205 { return true; }
    if c >= 178208 && c <= 183969 { return true; }
    if c >= 183984 && c <= 191456 { return true; }
    if c >= 194560 && c <= 195101 { return true; }
    if c >= 196608 && c <= 201546 { return true; }
    if c >= 201552 && c <= 205743 { return true; }
    return false;
}

fn xid_sigue(c: usize) -> bool {
    if c < 43808 {
        if c < 3872 {
            if c < 2790 {
                if c < 2185 {
                    if c < 1376 {
                        if c < 886 {
                            if c < 248 {
                                if c == 170 { return true; }
                                if c == 181 { return true; }
                                if c == 183 { return true; }
                                if c == 186 { return true; }
                                if c >= 192 && c <= 214 { return true; }
                                if c >= 216 && c <= 246 { return true; }
                                return false;
                            }
                            if c >= 248 && c <= 705 { return true; }
                            if c >= 710 && c <= 721 { return true; }
                            if c >= 736 && c <= 740 { return true; }
                            if c == 748 { return true; }
                            if c == 750 { return true; }
                            if c >= 768 && c <= 884 { return true; }
                            return false;
                        }
                        if c < 931 {
                            if c >= 886 && c <= 887 { return true; }
                            if c >= 891 && c <= 893 { return true; }
                            if c == 895 { return true; }
                            if c >= 902 && c <= 906 { return true; }
                            if c == 908 { return true; }
                            if c >= 910 && c <= 929 { return true; }
                            return false;
                        }
                        if c >= 931 && c <= 1013 { return true; }
                        if c >= 1015 && c <= 1153 { return true; }
                        if c >= 1155 && c <= 1159 { return true; }
                        if c >= 1162 && c <= 1327 { return true; }
                        if c >= 1329 && c <= 1366 { return true; }
                        if c == 1369 { return true; }
                        return false;
                    }
                    if c < 1759 {
                        if c < 1488 {
                            if c >= 1376 && c <= 1416 { return true; }
                            if c >= 1425 && c <= 1469 { return true; }
                            if c == 1471 { return true; }
                            if c >= 1473 && c <= 1474 { return true; }
                            if c >= 1476 && c <= 1477 { return true; }
                            if c == 1479 { return true; }
                            return false;
                        }
                        if c >= 1488 && c <= 1514 { return true; }
                        if c >= 1519 && c <= 1522 { return true; }
                        if c >= 1552 && c <= 1562 { return true; }
                        if c >= 1568 && c <= 1641 { return true; }
                        if c >= 1646 && c <= 1747 { return true; }
                        if c >= 1749 && c <= 1756 { return true; }
                        return false;
                    }
                    if c < 2042 {
                        if c >= 1759 && c <= 1768 { return true; }
                        if c >= 1770 && c <= 1788 { return true; }
                        if c == 1791 { return true; }
                        if c >= 1808 && c <= 1866 { return true; }
                        if c >= 1869 && c <= 1969 { return true; }
                        if c >= 1984 && c <= 2037 { return true; }
                        return false;
                    }
                    if c == 2042 { return true; }
                    if c == 2045 { return true; }
                    if c >= 2048 && c <= 2093 { return true; }
                    if c >= 2112 && c <= 2139 { return true; }
                    if c >= 2144 && c <= 2154 { return true; }
                    if c >= 2160 && c <= 2183 { return true; }
                    return false;
                }
                if c < 2602 {
                    if c < 2503 {
                        if c < 2447 {
                            if c >= 2185 && c <= 2190 { return true; }
                            if c >= 2200 && c <= 2273 { return true; }
                            if c >= 2275 && c <= 2403 { return true; }
                            if c >= 2406 && c <= 2415 { return true; }
                            if c >= 2417 && c <= 2435 { return true; }
                            if c >= 2437 && c <= 2444 { return true; }
                            return false;
                        }
                        if c >= 2447 && c <= 2448 { return true; }
                        if c >= 2451 && c <= 2472 { return true; }
                        if c >= 2474 && c <= 2480 { return true; }
                        if c == 2482 { return true; }
                        if c >= 2486 && c <= 2489 { return true; }
                        if c >= 2492 && c <= 2500 { return true; }
                        return false;
                    }
                    if c < 2556 {
                        if c >= 2503 && c <= 2504 { return true; }
                        if c >= 2507 && c <= 2510 { return true; }
                        if c == 2519 { return true; }
                        if c >= 2524 && c <= 2525 { return true; }
                        if c >= 2527 && c <= 2531 { return true; }
                        if c >= 2534 && c <= 2545 { return true; }
                        return false;
                    }
                    if c == 2556 { return true; }
                    if c == 2558 { return true; }
                    if c >= 2561 && c <= 2563 { return true; }
                    if c >= 2565 && c <= 2570 { return true; }
                    if c >= 2575 && c <= 2576 { return true; }
                    if c >= 2579 && c <= 2600 { return true; }
                    return false;
                }
                if c < 2689 {
                    if c < 2631 {
                        if c >= 2602 && c <= 2608 { return true; }
                        if c >= 2610 && c <= 2611 { return true; }
                        if c >= 2613 && c <= 2614 { return true; }
                        if c >= 2616 && c <= 2617 { return true; }
                        if c == 2620 { return true; }
                        if c >= 2622 && c <= 2626 { return true; }
                        return false;
                    }
                    if c >= 2631 && c <= 2632 { return true; }
                    if c >= 2635 && c <= 2637 { return true; }
                    if c == 2641 { return true; }
                    if c >= 2649 && c <= 2652 { return true; }
                    if c == 2654 { return true; }
                    if c >= 2662 && c <= 2677 { return true; }
                    return false;
                }
                if c < 2741 {
                    if c >= 2689 && c <= 2691 { return true; }
                    if c >= 2693 && c <= 2701 { return true; }
                    if c >= 2703 && c <= 2705 { return true; }
                    if c >= 2707 && c <= 2728 { return true; }
                    if c >= 2730 && c <= 2736 { return true; }
                    if c >= 2738 && c <= 2739 { return true; }
                    return false;
                }
                if c >= 2741 && c <= 2745 { return true; }
                if c >= 2748 && c <= 2757 { return true; }
                if c >= 2759 && c <= 2761 { return true; }
                if c >= 2763 && c <= 2765 { return true; }
                if c == 2768 { return true; }
                if c >= 2784 && c <= 2787 { return true; }
                return false;
            }
            if c < 3218 {
                if c < 2979 {
                    if c < 2901 {
                        if c < 2858 {
                            if c >= 2790 && c <= 2799 { return true; }
                            if c >= 2809 && c <= 2815 { return true; }
                            if c >= 2817 && c <= 2819 { return true; }
                            if c >= 2821 && c <= 2828 { return true; }
                            if c >= 2831 && c <= 2832 { return true; }
                            if c >= 2835 && c <= 2856 { return true; }
                            return false;
                        }
                        if c >= 2858 && c <= 2864 { return true; }
                        if c >= 2866 && c <= 2867 { return true; }
                        if c >= 2869 && c <= 2873 { return true; }
                        if c >= 2876 && c <= 2884 { return true; }
                        if c >= 2887 && c <= 2888 { return true; }
                        if c >= 2891 && c <= 2893 { return true; }
                        return false;
                    }
                    if c < 2949 {
                        if c >= 2901 && c <= 2903 { return true; }
                        if c >= 2908 && c <= 2909 { return true; }
                        if c >= 2911 && c <= 2915 { return true; }
                        if c >= 2918 && c <= 2927 { return true; }
                        if c == 2929 { return true; }
                        if c >= 2946 && c <= 2947 { return true; }
                        return false;
                    }
                    if c >= 2949 && c <= 2954 { return true; }
                    if c >= 2958 && c <= 2960 { return true; }
                    if c >= 2962 && c <= 2965 { return true; }
                    if c >= 2969 && c <= 2970 { return true; }
                    if c == 2972 { return true; }
                    if c >= 2974 && c <= 2975 { return true; }
                    return false;
                }
                if c < 3114 {
                    if c < 3024 {
                        if c >= 2979 && c <= 2980 { return true; }
                        if c >= 2984 && c <= 2986 { return true; }
                        if c >= 2990 && c <= 3001 { return true; }
                        if c >= 3006 && c <= 3010 { return true; }
                        if c >= 3014 && c <= 3016 { return true; }
                        if c >= 3018 && c <= 3021 { return true; }
                        return false;
                    }
                    if c == 3024 { return true; }
                    if c == 3031 { return true; }
                    if c >= 3046 && c <= 3055 { return true; }
                    if c >= 3072 && c <= 3084 { return true; }
                    if c >= 3086 && c <= 3088 { return true; }
                    if c >= 3090 && c <= 3112 { return true; }
                    return false;
                }
                if c < 3165 {
                    if c >= 3114 && c <= 3129 { return true; }
                    if c >= 3132 && c <= 3140 { return true; }
                    if c >= 3142 && c <= 3144 { return true; }
                    if c >= 3146 && c <= 3149 { return true; }
                    if c >= 3157 && c <= 3158 { return true; }
                    if c >= 3160 && c <= 3162 { return true; }
                    return false;
                }
                if c == 3165 { return true; }
                if c >= 3168 && c <= 3171 { return true; }
                if c >= 3174 && c <= 3183 { return true; }
                if c >= 3200 && c <= 3203 { return true; }
                if c >= 3205 && c <= 3212 { return true; }
                if c >= 3214 && c <= 3216 { return true; }
                return false;
            }
            if c < 3517 {
                if c < 3342 {
                    if c < 3285 {
                        if c >= 3218 && c <= 3240 { return true; }
                        if c >= 3242 && c <= 3251 { return true; }
                        if c >= 3253 && c <= 3257 { return true; }
                        if c >= 3260 && c <= 3268 { return true; }
                        if c >= 3270 && c <= 3272 { return true; }
                        if c >= 3274 && c <= 3277 { return true; }
                        return false;
                    }
                    if c >= 3285 && c <= 3286 { return true; }
                    if c >= 3293 && c <= 3294 { return true; }
                    if c >= 3296 && c <= 3299 { return true; }
                    if c >= 3302 && c <= 3311 { return true; }
                    if c >= 3313 && c <= 3315 { return true; }
                    if c >= 3328 && c <= 3340 { return true; }
                    return false;
                }
                if c < 3430 {
                    if c >= 3342 && c <= 3344 { return true; }
                    if c >= 3346 && c <= 3396 { return true; }
                    if c >= 3398 && c <= 3400 { return true; }
                    if c >= 3402 && c <= 3406 { return true; }
                    if c >= 3412 && c <= 3415 { return true; }
                    if c >= 3423 && c <= 3427 { return true; }
                    return false;
                }
                if c >= 3430 && c <= 3439 { return true; }
                if c >= 3450 && c <= 3455 { return true; }
                if c >= 3457 && c <= 3459 { return true; }
                if c >= 3461 && c <= 3478 { return true; }
                if c >= 3482 && c <= 3505 { return true; }
                if c >= 3507 && c <= 3515 { return true; }
                return false;
            }
            if c < 3716 {
                if c < 3558 {
                    if c == 3517 { return true; }
                    if c >= 3520 && c <= 3526 { return true; }
                    if c == 3530 { return true; }
                    if c >= 3535 && c <= 3540 { return true; }
                    if c == 3542 { return true; }
                    if c >= 3544 && c <= 3551 { return true; }
                    return false;
                }
                if c >= 3558 && c <= 3567 { return true; }
                if c >= 3570 && c <= 3571 { return true; }
                if c >= 3585 && c <= 3642 { return true; }
                if c >= 3648 && c <= 3662 { return true; }
                if c >= 3664 && c <= 3673 { return true; }
                if c >= 3713 && c <= 3714 { return true; }
                return false;
            }
            if c < 3782 {
                if c == 3716 { return true; }
                if c >= 3718 && c <= 3722 { return true; }
                if c >= 3724 && c <= 3747 { return true; }
                if c == 3749 { return true; }
                if c >= 3751 && c <= 3773 { return true; }
                if c >= 3776 && c <= 3780 { return true; }
                return false;
            }
            if c == 3782 { return true; }
            if c >= 3784 && c <= 3790 { return true; }
            if c >= 3792 && c <= 3801 { return true; }
            if c >= 3804 && c <= 3807 { return true; }
            if c == 3840 { return true; }
            if c >= 3864 && c <= 3865 { return true; }
            return false;
        }
        if c < 8126 {
            if c < 6016 {
                if c < 4786 {
                    if c < 4256 {
                        if c < 3953 {
                            if c >= 3872 && c <= 3881 { return true; }
                            if c == 3893 { return true; }
                            if c == 3895 { return true; }
                            if c == 3897 { return true; }
                            if c >= 3902 && c <= 3911 { return true; }
                            if c >= 3913 && c <= 3948 { return true; }
                            return false;
                        }
                        if c >= 3953 && c <= 3972 { return true; }
                        if c >= 3974 && c <= 3991 { return true; }
                        if c >= 3993 && c <= 4028 { return true; }
                        if c == 4038 { return true; }
                        if c >= 4096 && c <= 4169 { return true; }
                        if c >= 4176 && c <= 4253 { return true; }
                        return false;
                    }
                    if c < 4688 {
                        if c >= 4256 && c <= 4293 { return true; }
                        if c == 4295 { return true; }
                        if c == 4301 { return true; }
                        if c >= 4304 && c <= 4346 { return true; }
                        if c >= 4348 && c <= 4680 { return true; }
                        if c >= 4682 && c <= 4685 { return true; }
                        return false;
                    }
                    if c >= 4688 && c <= 4694 { return true; }
                    if c == 4696 { return true; }
                    if c >= 4698 && c <= 4701 { return true; }
                    if c >= 4704 && c <= 4744 { return true; }
                    if c >= 4746 && c <= 4749 { return true; }
                    if c >= 4752 && c <= 4784 { return true; }
                    return false;
                }
                if c < 5112 {
                    if c < 4882 {
                        if c >= 4786 && c <= 4789 { return true; }
                        if c >= 4792 && c <= 4798 { return true; }
                        if c == 4800 { return true; }
                        if c >= 4802 && c <= 4805 { return true; }
                        if c >= 4808 && c <= 4822 { return true; }
                        if c >= 4824 && c <= 4880 { return true; }
                        return false;
                    }
                    if c >= 4882 && c <= 4885 { return true; }
                    if c >= 4888 && c <= 4954 { return true; }
                    if c >= 4957 && c <= 4959 { return true; }
                    if c >= 4969 && c <= 4977 { return true; }
                    if c >= 4992 && c <= 5007 { return true; }
                    if c >= 5024 && c <= 5109 { return true; }
                    return false;
                }
                if c < 5888 {
                    if c >= 5112 && c <= 5117 { return true; }
                    if c >= 5121 && c <= 5740 { return true; }
                    if c >= 5743 && c <= 5759 { return true; }
                    if c >= 5761 && c <= 5786 { return true; }
                    if c >= 5792 && c <= 5866 { return true; }
                    if c >= 5870 && c <= 5880 { return true; }
                    return false;
                }
                if c >= 5888 && c <= 5909 { return true; }
                if c >= 5919 && c <= 5940 { return true; }
                if c >= 5952 && c <= 5971 { return true; }
                if c >= 5984 && c <= 5996 { return true; }
                if c >= 5998 && c <= 6000 { return true; }
                if c >= 6002 && c <= 6003 { return true; }
                return false;
            }
            if c < 6847 {
                if c < 6470 {
                    if c < 6176 {
                        if c >= 6016 && c <= 6099 { return true; }
                        if c == 6103 { return true; }
                        if c >= 6108 && c <= 6109 { return true; }
                        if c >= 6112 && c <= 6121 { return true; }
                        if c >= 6155 && c <= 6157 { return true; }
                        if c >= 6159 && c <= 6169 { return true; }
                        return false;
                    }
                    if c >= 6176 && c <= 6264 { return true; }
                    if c >= 6272 && c <= 6314 { return true; }
                    if c >= 6320 && c <= 6389 { return true; }
                    if c >= 6400 && c <= 6430 { return true; }
                    if c >= 6432 && c <= 6443 { return true; }
                    if c >= 6448 && c <= 6459 { return true; }
                    return false;
                }
                if c < 6688 {
                    if c >= 6470 && c <= 6509 { return true; }
                    if c >= 6512 && c <= 6516 { return true; }
                    if c >= 6528 && c <= 6571 { return true; }
                    if c >= 6576 && c <= 6601 { return true; }
                    if c >= 6608 && c <= 6618 { return true; }
                    if c >= 6656 && c <= 6683 { return true; }
                    return false;
                }
                if c >= 6688 && c <= 6750 { return true; }
                if c >= 6752 && c <= 6780 { return true; }
                if c >= 6783 && c <= 6793 { return true; }
                if c >= 6800 && c <= 6809 { return true; }
                if c == 6823 { return true; }
                if c >= 6832 && c <= 6845 { return true; }
                return false;
            }
            if c < 7380 {
                if c < 7232 {
                    if c >= 6847 && c <= 6862 { return true; }
                    if c >= 6912 && c <= 6988 { return true; }
                    if c >= 6992 && c <= 7001 { return true; }
                    if c >= 7019 && c <= 7027 { return true; }
                    if c >= 7040 && c <= 7155 { return true; }
                    if c >= 7168 && c <= 7223 { return true; }
                    return false;
                }
                if c >= 7232 && c <= 7241 { return true; }
                if c >= 7245 && c <= 7293 { return true; }
                if c >= 7296 && c <= 7304 { return true; }
                if c >= 7312 && c <= 7354 { return true; }
                if c >= 7357 && c <= 7359 { return true; }
                if c >= 7376 && c <= 7378 { return true; }
                return false;
            }
            if c < 8025 {
                if c >= 7380 && c <= 7418 { return true; }
                if c >= 7424 && c <= 7957 { return true; }
                if c >= 7960 && c <= 7965 { return true; }
                if c >= 7968 && c <= 8005 { return true; }
                if c >= 8008 && c <= 8013 { return true; }
                if c >= 8016 && c <= 8023 { return true; }
                return false;
            }
            if c == 8025 { return true; }
            if c == 8027 { return true; }
            if c == 8029 { return true; }
            if c >= 8031 && c <= 8061 { return true; }
            if c >= 8064 && c <= 8116 { return true; }
            if c >= 8118 && c <= 8124 { return true; }
            return false;
        }
        if c < 12337 {
            if c < 8490 {
                if c < 8336 {
                    if c < 8178 {
                        if c == 8126 { return true; }
                        if c >= 8130 && c <= 8132 { return true; }
                        if c >= 8134 && c <= 8140 { return true; }
                        if c >= 8144 && c <= 8147 { return true; }
                        if c >= 8150 && c <= 8155 { return true; }
                        if c >= 8160 && c <= 8172 { return true; }
                        return false;
                    }
                    if c >= 8178 && c <= 8180 { return true; }
                    if c >= 8182 && c <= 8188 { return true; }
                    if c >= 8255 && c <= 8256 { return true; }
                    if c == 8276 { return true; }
                    if c == 8305 { return true; }
                    if c == 8319 { return true; }
                    return false;
                }
                if c < 8458 {
                    if c >= 8336 && c <= 8348 { return true; }
                    if c >= 8400 && c <= 8412 { return true; }
                    if c == 8417 { return true; }
                    if c >= 8421 && c <= 8432 { return true; }
                    if c == 8450 { return true; }
                    if c == 8455 { return true; }
                    return false;
                }
                if c >= 8458 && c <= 8467 { return true; }
                if c == 8469 { return true; }
                if c >= 8472 && c <= 8477 { return true; }
                if c == 8484 { return true; }
                if c == 8486 { return true; }
                if c == 8488 { return true; }
                return false;
            }
            if c < 11647 {
                if c < 11499 {
                    if c >= 8490 && c <= 8505 { return true; }
                    if c >= 8508 && c <= 8511 { return true; }
                    if c >= 8517 && c <= 8521 { return true; }
                    if c == 8526 { return true; }
                    if c >= 8544 && c <= 8584 { return true; }
                    if c >= 11264 && c <= 11492 { return true; }
                    return false;
                }
                if c >= 11499 && c <= 11507 { return true; }
                if c >= 11520 && c <= 11557 { return true; }
                if c == 11559 { return true; }
                if c == 11565 { return true; }
                if c >= 11568 && c <= 11623 { return true; }
                if c == 11631 { return true; }
                return false;
            }
            if c < 11720 {
                if c >= 11647 && c <= 11670 { return true; }
                if c >= 11680 && c <= 11686 { return true; }
                if c >= 11688 && c <= 11694 { return true; }
                if c >= 11696 && c <= 11702 { return true; }
                if c >= 11704 && c <= 11710 { return true; }
                if c >= 11712 && c <= 11718 { return true; }
                return false;
            }
            if c >= 11720 && c <= 11726 { return true; }
            if c >= 11728 && c <= 11734 { return true; }
            if c >= 11736 && c <= 11742 { return true; }
            if c >= 11744 && c <= 11775 { return true; }
            if c >= 12293 && c <= 12295 { return true; }
            if c >= 12321 && c <= 12335 { return true; }
            return false;
        }
        if c < 42965 {
            if c < 19968 {
                if c < 12540 {
                    if c >= 12337 && c <= 12341 { return true; }
                    if c >= 12344 && c <= 12348 { return true; }
                    if c >= 12353 && c <= 12438 { return true; }
                    if c >= 12441 && c <= 12442 { return true; }
                    if c >= 12445 && c <= 12447 { return true; }
                    if c >= 12449 && c <= 12538 { return true; }
                    return false;
                }
                if c >= 12540 && c <= 12543 { return true; }
                if c >= 12549 && c <= 12591 { return true; }
                if c >= 12593 && c <= 12686 { return true; }
                if c >= 12704 && c <= 12735 { return true; }
                if c >= 12784 && c <= 12799 { return true; }
                if c >= 13312 && c <= 19903 { return true; }
                return false;
            }
            if c < 42623 {
                if c >= 19968 && c <= 42124 { return true; }
                if c >= 42192 && c <= 42237 { return true; }
                if c >= 42240 && c <= 42508 { return true; }
                if c >= 42512 && c <= 42539 { return true; }
                if c >= 42560 && c <= 42607 { return true; }
                if c >= 42612 && c <= 42621 { return true; }
                return false;
            }
            if c >= 42623 && c <= 42737 { return true; }
            if c >= 42775 && c <= 42783 { return true; }
            if c >= 42786 && c <= 42888 { return true; }
            if c >= 42891 && c <= 42954 { return true; }
            if c >= 42960 && c <= 42961 { return true; }
            if c == 42963 { return true; }
            return false;
        }
        if c < 43471 {
            if c < 43232 {
                if c >= 42965 && c <= 42969 { return true; }
                if c >= 42994 && c <= 43047 { return true; }
                if c == 43052 { return true; }
                if c >= 43072 && c <= 43123 { return true; }
                if c >= 43136 && c <= 43205 { return true; }
                if c >= 43216 && c <= 43225 { return true; }
                return false;
            }
            if c >= 43232 && c <= 43255 { return true; }
            if c == 43259 { return true; }
            if c >= 43261 && c <= 43309 { return true; }
            if c >= 43312 && c <= 43347 { return true; }
            if c >= 43360 && c <= 43388 { return true; }
            if c >= 43392 && c <= 43456 { return true; }
            return false;
        }
        if c < 43642 {
            if c >= 43471 && c <= 43481 { return true; }
            if c >= 43488 && c <= 43518 { return true; }
            if c >= 43520 && c <= 43574 { return true; }
            if c >= 43584 && c <= 43597 { return true; }
            if c >= 43600 && c <= 43609 { return true; }
            if c >= 43616 && c <= 43638 { return true; }
            return false;
        }
        if c < 43762 {
            if c >= 43642 && c <= 43714 { return true; }
            if c >= 43739 && c <= 43741 { return true; }
            if c >= 43744 && c <= 43759 { return true; }
            return false;
        }
        if c >= 43762 && c <= 43766 { return true; }
        if c >= 43777 && c <= 43782 { return true; }
        if c >= 43785 && c <= 43790 { return true; }
        if c >= 43793 && c <= 43798 { return true; }
        return false;
    }
    if c < 71991 {
        if c < 67872 {
            if c < 65576 {
                if c < 64914 {
                    if c < 64256 {
                        if c < 44016 {
                            if c >= 43808 && c <= 43814 { return true; }
                            if c >= 43816 && c <= 43822 { return true; }
                            if c >= 43824 && c <= 43866 { return true; }
                            if c >= 43868 && c <= 43881 { return true; }
                            if c >= 43888 && c <= 44010 { return true; }
                            if c >= 44012 && c <= 44013 { return true; }
                            return false;
                        }
                        if c >= 44016 && c <= 44025 { return true; }
                        if c >= 44032 && c <= 55203 { return true; }
                        if c >= 55216 && c <= 55238 { return true; }
                        if c >= 55243 && c <= 55291 { return true; }
                        if c >= 63744 && c <= 64109 { return true; }
                        if c >= 64112 && c <= 64217 { return true; }
                        return false;
                    }
                    if c < 64320 {
                        if c >= 64256 && c <= 64262 { return true; }
                        if c >= 64275 && c <= 64279 { return true; }
                        if c >= 64285 && c <= 64296 { return true; }
                        if c >= 64298 && c <= 64310 { return true; }
                        if c >= 64312 && c <= 64316 { return true; }
                        if c == 64318 { return true; }
                        return false;
                    }
                    if c >= 64320 && c <= 64321 { return true; }
                    if c >= 64323 && c <= 64324 { return true; }
                    if c >= 64326 && c <= 64433 { return true; }
                    if c >= 64467 && c <= 64605 { return true; }
                    if c >= 64612 && c <= 64829 { return true; }
                    if c >= 64848 && c <= 64911 { return true; }
                    return false;
                }
                if c < 65151 {
                    if c < 65137 {
                        if c >= 64914 && c <= 64967 { return true; }
                        if c >= 65008 && c <= 65017 { return true; }
                        if c >= 65024 && c <= 65039 { return true; }
                        if c >= 65056 && c <= 65071 { return true; }
                        if c >= 65075 && c <= 65076 { return true; }
                        if c >= 65101 && c <= 65103 { return true; }
                        return false;
                    }
                    if c == 65137 { return true; }
                    if c == 65139 { return true; }
                    if c == 65143 { return true; }
                    if c == 65145 { return true; }
                    if c == 65147 { return true; }
                    if c == 65149 { return true; }
                    return false;
                }
                if c < 65474 {
                    if c >= 65151 && c <= 65276 { return true; }
                    if c >= 65296 && c <= 65305 { return true; }
                    if c >= 65313 && c <= 65338 { return true; }
                    if c == 65343 { return true; }
                    if c >= 65345 && c <= 65370 { return true; }
                    if c >= 65382 && c <= 65470 { return true; }
                    return false;
                }
                if c >= 65474 && c <= 65479 { return true; }
                if c >= 65482 && c <= 65487 { return true; }
                if c >= 65490 && c <= 65495 { return true; }
                if c >= 65498 && c <= 65500 { return true; }
                if c >= 65536 && c <= 65547 { return true; }
                if c >= 65549 && c <= 65574 { return true; }
                return false;
            }
            if c < 66940 {
                if c < 66384 {
                    if c < 66045 {
                        if c >= 65576 && c <= 65594 { return true; }
                        if c >= 65596 && c <= 65597 { return true; }
                        if c >= 65599 && c <= 65613 { return true; }
                        if c >= 65616 && c <= 65629 { return true; }
                        if c >= 65664 && c <= 65786 { return true; }
                        if c >= 65856 && c <= 65908 { return true; }
                        return false;
                    }
                    if c == 66045 { return true; }
                    if c >= 66176 && c <= 66204 { return true; }
                    if c >= 66208 && c <= 66256 { return true; }
                    if c == 66272 { return true; }
                    if c >= 66304 && c <= 66335 { return true; }
                    if c >= 66349 && c <= 66378 { return true; }
                    return false;
                }
                if c < 66720 {
                    if c >= 66384 && c <= 66426 { return true; }
                    if c >= 66432 && c <= 66461 { return true; }
                    if c >= 66464 && c <= 66499 { return true; }
                    if c >= 66504 && c <= 66511 { return true; }
                    if c >= 66513 && c <= 66517 { return true; }
                    if c >= 66560 && c <= 66717 { return true; }
                    return false;
                }
                if c >= 66720 && c <= 66729 { return true; }
                if c >= 66736 && c <= 66771 { return true; }
                if c >= 66776 && c <= 66811 { return true; }
                if c >= 66816 && c <= 66855 { return true; }
                if c >= 66864 && c <= 66915 { return true; }
                if c >= 66928 && c <= 66938 { return true; }
                return false;
            }
            if c < 67506 {
                if c < 67003 {
                    if c >= 66940 && c <= 66954 { return true; }
                    if c >= 66956 && c <= 66962 { return true; }
                    if c >= 66964 && c <= 66965 { return true; }
                    if c >= 66967 && c <= 66977 { return true; }
                    if c >= 66979 && c <= 66993 { return true; }
                    if c >= 66995 && c <= 67001 { return true; }
                    return false;
                }
                if c >= 67003 && c <= 67004 { return true; }
                if c >= 67072 && c <= 67382 { return true; }
                if c >= 67392 && c <= 67413 { return true; }
                if c >= 67424 && c <= 67431 { return true; }
                if c >= 67456 && c <= 67461 { return true; }
                if c >= 67463 && c <= 67504 { return true; }
                return false;
            }
            if c < 67647 {
                if c >= 67506 && c <= 67514 { return true; }
                if c >= 67584 && c <= 67589 { return true; }
                if c == 67592 { return true; }
                if c >= 67594 && c <= 67637 { return true; }
                if c >= 67639 && c <= 67640 { return true; }
                if c == 67644 { return true; }
                return false;
            }
            if c >= 67647 && c <= 67669 { return true; }
            if c >= 67680 && c <= 67702 { return true; }
            if c >= 67712 && c <= 67742 { return true; }
            if c >= 67808 && c <= 67826 { return true; }
            if c >= 67828 && c <= 67829 { return true; }
            if c >= 67840 && c <= 67861 { return true; }
            return false;
        }
        if c < 70163 {
            if c < 69291 {
                if c < 68288 {
                    if c < 68117 {
                        if c >= 67872 && c <= 67897 { return true; }
                        if c >= 67968 && c <= 68023 { return true; }
                        if c >= 68030 && c <= 68031 { return true; }
                        if c >= 68096 && c <= 68099 { return true; }
                        if c >= 68101 && c <= 68102 { return true; }
                        if c >= 68108 && c <= 68115 { return true; }
                        return false;
                    }
                    if c >= 68117 && c <= 68119 { return true; }
                    if c >= 68121 && c <= 68149 { return true; }
                    if c >= 68152 && c <= 68154 { return true; }
                    if c == 68159 { return true; }
                    if c >= 68192 && c <= 68220 { return true; }
                    if c >= 68224 && c <= 68252 { return true; }
                    return false;
                }
                if c < 68608 {
                    if c >= 68288 && c <= 68295 { return true; }
                    if c >= 68297 && c <= 68326 { return true; }
                    if c >= 68352 && c <= 68405 { return true; }
                    if c >= 68416 && c <= 68437 { return true; }
                    if c >= 68448 && c <= 68466 { return true; }
                    if c >= 68480 && c <= 68497 { return true; }
                    return false;
                }
                if c >= 68608 && c <= 68680 { return true; }
                if c >= 68736 && c <= 68786 { return true; }
                if c >= 68800 && c <= 68850 { return true; }
                if c >= 68864 && c <= 68903 { return true; }
                if c >= 68912 && c <= 68921 { return true; }
                if c >= 69248 && c <= 69289 { return true; }
                return false;
            }
            if c < 69840 {
                if c < 69552 {
                    if c >= 69291 && c <= 69292 { return true; }
                    if c >= 69296 && c <= 69297 { return true; }
                    if c >= 69373 && c <= 69404 { return true; }
                    if c == 69415 { return true; }
                    if c >= 69424 && c <= 69456 { return true; }
                    if c >= 69488 && c <= 69509 { return true; }
                    return false;
                }
                if c >= 69552 && c <= 69572 { return true; }
                if c >= 69600 && c <= 69622 { return true; }
                if c >= 69632 && c <= 69702 { return true; }
                if c >= 69734 && c <= 69749 { return true; }
                if c >= 69759 && c <= 69818 { return true; }
                if c == 69826 { return true; }
                return false;
            }
            if c < 70006 {
                if c >= 69840 && c <= 69864 { return true; }
                if c >= 69872 && c <= 69881 { return true; }
                if c >= 69888 && c <= 69940 { return true; }
                if c >= 69942 && c <= 69951 { return true; }
                if c >= 69956 && c <= 69959 { return true; }
                if c >= 69968 && c <= 70003 { return true; }
                return false;
            }
            if c == 70006 { return true; }
            if c >= 70016 && c <= 70084 { return true; }
            if c >= 70089 && c <= 70092 { return true; }
            if c >= 70094 && c <= 70106 { return true; }
            if c == 70108 { return true; }
            if c >= 70144 && c <= 70161 { return true; }
            return false;
        }
        if c < 70656 {
            if c < 70419 {
                if c < 70303 {
                    if c >= 70163 && c <= 70199 { return true; }
                    if c >= 70206 && c <= 70209 { return true; }
                    if c >= 70272 && c <= 70278 { return true; }
                    if c == 70280 { return true; }
                    if c >= 70282 && c <= 70285 { return true; }
                    if c >= 70287 && c <= 70301 { return true; }
                    return false;
                }
                if c >= 70303 && c <= 70312 { return true; }
                if c >= 70320 && c <= 70378 { return true; }
                if c >= 70384 && c <= 70393 { return true; }
                if c >= 70400 && c <= 70403 { return true; }
                if c >= 70405 && c <= 70412 { return true; }
                if c >= 70415 && c <= 70416 { return true; }
                return false;
            }
            if c < 70475 {
                if c >= 70419 && c <= 70440 { return true; }
                if c >= 70442 && c <= 70448 { return true; }
                if c >= 70450 && c <= 70451 { return true; }
                if c >= 70453 && c <= 70457 { return true; }
                if c >= 70459 && c <= 70468 { return true; }
                if c >= 70471 && c <= 70472 { return true; }
                return false;
            }
            if c >= 70475 && c <= 70477 { return true; }
            if c == 70480 { return true; }
            if c == 70487 { return true; }
            if c >= 70493 && c <= 70499 { return true; }
            if c >= 70502 && c <= 70508 { return true; }
            if c >= 70512 && c <= 70516 { return true; }
            return false;
        }
        if c < 71296 {
            if c < 71040 {
                if c >= 70656 && c <= 70730 { return true; }
                if c >= 70736 && c <= 70745 { return true; }
                if c >= 70750 && c <= 70753 { return true; }
                if c >= 70784 && c <= 70853 { return true; }
                if c == 70855 { return true; }
                if c >= 70864 && c <= 70873 { return true; }
                return false;
            }
            if c >= 71040 && c <= 71093 { return true; }
            if c >= 71096 && c <= 71104 { return true; }
            if c >= 71128 && c <= 71133 { return true; }
            if c >= 71168 && c <= 71232 { return true; }
            if c == 71236 { return true; }
            if c >= 71248 && c <= 71257 { return true; }
            return false;
        }
        if c < 71680 {
            if c >= 71296 && c <= 71352 { return true; }
            if c >= 71360 && c <= 71369 { return true; }
            if c >= 71424 && c <= 71450 { return true; }
            if c >= 71453 && c <= 71467 { return true; }
            if c >= 71472 && c <= 71481 { return true; }
            if c >= 71488 && c <= 71494 { return true; }
            return false;
        }
        if c < 71945 {
            if c >= 71680 && c <= 71738 { return true; }
            if c >= 71840 && c <= 71913 { return true; }
            if c >= 71935 && c <= 71942 { return true; }
            return false;
        }
        if c == 71945 { return true; }
        if c >= 71948 && c <= 71955 { return true; }
        if c >= 71957 && c <= 71958 { return true; }
        if c >= 71960 && c <= 71989 { return true; }
        return false;
    }
    if c < 119995 {
        if c < 92784 {
            if c < 73023 {
                if c < 72704 {
                    if c < 72163 {
                        if c >= 71991 && c <= 71992 { return true; }
                        if c >= 71995 && c <= 72003 { return true; }
                        if c >= 72016 && c <= 72025 { return true; }
                        if c >= 72096 && c <= 72103 { return true; }
                        if c >= 72106 && c <= 72151 { return true; }
                        if c >= 72154 && c <= 72161 { return true; }
                        return false;
                    }
                    if c >= 72163 && c <= 72164 { return true; }
                    if c >= 72192 && c <= 72254 { return true; }
                    if c == 72263 { return true; }
                    if c >= 72272 && c <= 72345 { return true; }
                    if c == 72349 { return true; }
                    if c >= 72368 && c <= 72440 { return true; }
                    return false;
                }
                if c < 72873 {
                    if c >= 72704 && c <= 72712 { return true; }
                    if c >= 72714 && c <= 72758 { return true; }
                    if c >= 72760 && c <= 72768 { return true; }
                    if c >= 72784 && c <= 72793 { return true; }
                    if c >= 72818 && c <= 72847 { return true; }
                    if c >= 72850 && c <= 72871 { return true; }
                    return false;
                }
                if c >= 72873 && c <= 72886 { return true; }
                if c >= 72960 && c <= 72966 { return true; }
                if c >= 72968 && c <= 72969 { return true; }
                if c >= 72971 && c <= 73014 { return true; }
                if c == 73018 { return true; }
                if c >= 73020 && c <= 73021 { return true; }
                return false;
            }
            if c < 73552 {
                if c < 73107 {
                    if c >= 73023 && c <= 73031 { return true; }
                    if c >= 73040 && c <= 73049 { return true; }
                    if c >= 73056 && c <= 73061 { return true; }
                    if c >= 73063 && c <= 73064 { return true; }
                    if c >= 73066 && c <= 73102 { return true; }
                    if c >= 73104 && c <= 73105 { return true; }
                    return false;
                }
                if c >= 73107 && c <= 73112 { return true; }
                if c >= 73120 && c <= 73129 { return true; }
                if c >= 73440 && c <= 73462 { return true; }
                if c >= 73472 && c <= 73488 { return true; }
                if c >= 73490 && c <= 73530 { return true; }
                if c >= 73534 && c <= 73538 { return true; }
                return false;
            }
            if c < 77824 {
                if c >= 73552 && c <= 73561 { return true; }
                if c == 73648 { return true; }
                if c >= 73728 && c <= 74649 { return true; }
                if c >= 74752 && c <= 74862 { return true; }
                if c >= 74880 && c <= 75075 { return true; }
                if c >= 77712 && c <= 77808 { return true; }
                return false;
            }
            if c >= 77824 && c <= 78895 { return true; }
            if c >= 78912 && c <= 78933 { return true; }
            if c >= 82944 && c <= 83526 { return true; }
            if c >= 92160 && c <= 92728 { return true; }
            if c >= 92736 && c <= 92766 { return true; }
            if c >= 92768 && c <= 92777 { return true; }
            return false;
        }
        if c < 110928 {
            if c < 94095 {
                if c < 93008 {
                    if c >= 92784 && c <= 92862 { return true; }
                    if c >= 92864 && c <= 92873 { return true; }
                    if c >= 92880 && c <= 92909 { return true; }
                    if c >= 92912 && c <= 92916 { return true; }
                    if c >= 92928 && c <= 92982 { return true; }
                    if c >= 92992 && c <= 92995 { return true; }
                    return false;
                }
                if c >= 93008 && c <= 93017 { return true; }
                if c >= 93027 && c <= 93047 { return true; }
                if c >= 93053 && c <= 93071 { return true; }
                if c >= 93760 && c <= 93823 { return true; }
                if c >= 93952 && c <= 94026 { return true; }
                if c >= 94031 && c <= 94087 { return true; }
                return false;
            }
            if c < 101632 {
                if c >= 94095 && c <= 94111 { return true; }
                if c >= 94176 && c <= 94177 { return true; }
                if c >= 94179 && c <= 94180 { return true; }
                if c >= 94192 && c <= 94193 { return true; }
                if c >= 94208 && c <= 100343 { return true; }
                if c >= 100352 && c <= 101589 { return true; }
                return false;
            }
            if c >= 101632 && c <= 101640 { return true; }
            if c >= 110576 && c <= 110579 { return true; }
            if c >= 110581 && c <= 110587 { return true; }
            if c >= 110589 && c <= 110590 { return true; }
            if c >= 110592 && c <= 110882 { return true; }
            if c == 110898 { return true; }
            return false;
        }
        if c < 119149 {
            if c < 113792 {
                if c >= 110928 && c <= 110930 { return true; }
                if c == 110933 { return true; }
                if c >= 110948 && c <= 110951 { return true; }
                if c >= 110960 && c <= 111355 { return true; }
                if c >= 113664 && c <= 113770 { return true; }
                if c >= 113776 && c <= 113788 { return true; }
                return false;
            }
            if c >= 113792 && c <= 113800 { return true; }
            if c >= 113808 && c <= 113817 { return true; }
            if c >= 113821 && c <= 113822 { return true; }
            if c >= 118528 && c <= 118573 { return true; }
            if c >= 118576 && c <= 118598 { return true; }
            if c >= 119141 && c <= 119145 { return true; }
            return false;
        }
        if c < 119894 {
            if c >= 119149 && c <= 119154 { return true; }
            if c >= 119163 && c <= 119170 { return true; }
            if c >= 119173 && c <= 119179 { return true; }
            if c >= 119210 && c <= 119213 { return true; }
            if c >= 119362 && c <= 119364 { return true; }
            if c >= 119808 && c <= 119892 { return true; }
            return false;
        }
        if c >= 119894 && c <= 119964 { return true; }
        if c >= 119966 && c <= 119967 { return true; }
        if c == 119970 { return true; }
        if c >= 119973 && c <= 119974 { return true; }
        if c >= 119977 && c <= 119980 { return true; }
        if c >= 119982 && c <= 119993 { return true; }
        return false;
    }
    if c < 124909 {
        if c < 121344 {
            if c < 120488 {
                if c < 120094 {
                    if c == 119995 { return true; }
                    if c >= 119997 && c <= 120003 { return true; }
                    if c >= 120005 && c <= 120069 { return true; }
                    if c >= 120071 && c <= 120074 { return true; }
                    if c >= 120077 && c <= 120084 { return true; }
                    if c >= 120086 && c <= 120092 { return true; }
                    return false;
                }
                if c >= 120094 && c <= 120121 { return true; }
                if c >= 120123 && c <= 120126 { return true; }
                if c >= 120128 && c <= 120132 { return true; }
                if c == 120134 { return true; }
                if c >= 120138 && c <= 120144 { return true; }
                if c >= 120146 && c <= 120485 { return true; }
                return false;
            }
            if c < 120656 {
                if c >= 120488 && c <= 120512 { return true; }
                if c >= 120514 && c <= 120538 { return true; }
                if c >= 120540 && c <= 120570 { return true; }
                if c >= 120572 && c <= 120596 { return true; }
                if c >= 120598 && c <= 120628 { return true; }
                if c >= 120630 && c <= 120654 { return true; }
                return false;
            }
            if c >= 120656 && c <= 120686 { return true; }
            if c >= 120688 && c <= 120712 { return true; }
            if c >= 120714 && c <= 120744 { return true; }
            if c >= 120746 && c <= 120770 { return true; }
            if c >= 120772 && c <= 120779 { return true; }
            if c >= 120782 && c <= 120831 { return true; }
            return false;
        }
        if c < 122918 {
            if c < 122624 {
                if c >= 121344 && c <= 121398 { return true; }
                if c >= 121403 && c <= 121452 { return true; }
                if c == 121461 { return true; }
                if c == 121476 { return true; }
                if c >= 121499 && c <= 121503 { return true; }
                if c >= 121505 && c <= 121519 { return true; }
                return false;
            }
            if c >= 122624 && c <= 122654 { return true; }
            if c >= 122661 && c <= 122666 { return true; }
            if c >= 122880 && c <= 122886 { return true; }
            if c >= 122888 && c <= 122904 { return true; }
            if c >= 122907 && c <= 122913 { return true; }
            if c >= 122915 && c <= 122916 { return true; }
            return false;
        }
        if c < 123214 {
            if c >= 122918 && c <= 122922 { return true; }
            if c >= 122928 && c <= 122989 { return true; }
            if c == 123023 { return true; }
            if c >= 123136 && c <= 123180 { return true; }
            if c >= 123184 && c <= 123197 { return true; }
            if c >= 123200 && c <= 123209 { return true; }
            return false;
        }
        if c == 123214 { return true; }
        if c >= 123536 && c <= 123566 { return true; }
        if c >= 123584 && c <= 123641 { return true; }
        if c >= 124112 && c <= 124153 { return true; }
        if c >= 124896 && c <= 124902 { return true; }
        if c >= 124904 && c <= 124907 { return true; }
        return false;
    }
    if c < 126555 {
        if c < 126516 {
            if c < 126464 {
                if c >= 124909 && c <= 124910 { return true; }
                if c >= 124912 && c <= 124926 { return true; }
                if c >= 124928 && c <= 125124 { return true; }
                if c >= 125136 && c <= 125142 { return true; }
                if c >= 125184 && c <= 125259 { return true; }
                if c >= 125264 && c <= 125273 { return true; }
                return false;
            }
            if c >= 126464 && c <= 126467 { return true; }
            if c >= 126469 && c <= 126495 { return true; }
            if c >= 126497 && c <= 126498 { return true; }
            if c == 126500 { return true; }
            if c == 126503 { return true; }
            if c >= 126505 && c <= 126514 { return true; }
            return false;
        }
        if c < 126539 {
            if c >= 126516 && c <= 126519 { return true; }
            if c == 126521 { return true; }
            if c == 126523 { return true; }
            if c == 126530 { return true; }
            if c == 126535 { return true; }
            if c == 126537 { return true; }
            return false;
        }
        if c == 126539 { return true; }
        if c >= 126541 && c <= 126543 { return true; }
        if c >= 126545 && c <= 126546 { return true; }
        if c == 126548 { return true; }
        if c == 126551 { return true; }
        if c == 126553 { return true; }
        return false;
    }
    if c < 126625 {
        if c < 126572 {
            if c == 126555 { return true; }
            if c == 126557 { return true; }
            if c == 126559 { return true; }
            if c >= 126561 && c <= 126562 { return true; }
            if c == 126564 { return true; }
            if c >= 126567 && c <= 126570 { return true; }
            return false;
        }
        if c >= 126572 && c <= 126578 { return true; }
        if c >= 126580 && c <= 126583 { return true; }
        if c >= 126585 && c <= 126588 { return true; }
        if c == 126590 { return true; }
        if c >= 126592 && c <= 126601 { return true; }
        if c >= 126603 && c <= 126619 { return true; }
        return false;
    }
    if c < 177984 {
        if c >= 126625 && c <= 126627 { return true; }
        if c >= 126629 && c <= 126633 { return true; }
        if c >= 126635 && c <= 126651 { return true; }
        if c >= 130032 && c <= 130041 { return true; }
        if c >= 131072 && c <= 173791 { return true; }
        if c >= 173824 && c <= 177977 { return true; }
        return false;
    }
    if c < 194560 {
        if c >= 177984 && c <= 178205 { return true; }
        if c >= 178208 && c <= 183969 { return true; }
        if c >= 183984 && c <= 191456 { return true; }
        return false;
    }
    if c >= 194560 && c <= 195101 { return true; }
    if c >= 196608 && c <= 201546 { return true; }
    if c >= 201552 && c <= 205743 { return true; }
    if c >= 917760 && c <= 917999 { return true; }
    return false;
}
