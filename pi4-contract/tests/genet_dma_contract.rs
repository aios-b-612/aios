use pi4_contract::*;

#[test]
fn ring_cfg_bit_is_default_q_not_shifted() {
    assert_eq!(dma_ring_cfg_enable_bit(DEFAULT_Q), 1u32 << 16);
    assert_ne!(
        dma_ring_cfg_enable_bit(DEFAULT_Q),
        1u32 << (DEFAULT_Q + DMA_RING_BUF_EN_SHIFT),
        "RING_CFG must NOT use CTRL shift — that was the TX stall bug"
    );
}

#[test]
fn ctrl_bit_uses_shift() {
    assert_eq!(
        dma_ctrl_ring_enable_bit(DEFAULT_Q),
        1u32 << (DEFAULT_Q + DMA_RING_BUF_EN_SHIFT)
    );
}

#[test]
fn ring_cfg_and_ctrl_bits_differ() {
    assert!(ring_cfg_must_differ_from_ctrl(DEFAULT_Q));
}

#[test]
fn beacon_ethertype_and_prefix() {
    assert_eq!(AIOS_BOOT_ETHERTYPE, 0x88b5);
    assert!(AIOS_BOOT_PREFIX.starts_with("AIOS-BOOT"));
}

#[test]
fn known_good_and_bad_genetd_md5_differ() {
    assert_ne!(GENETD_M1_MD5, GENETD_M2_HANG_MD5);
    assert_eq!(GENETD_M1_MD5.len(), 32);
    assert_eq!(GENETD_M2_HANG_MD5.len(), 32);
}
