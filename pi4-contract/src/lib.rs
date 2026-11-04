//! Contratos de regressão do bring-up Pi 4 (GENET TX / SDHCI).
//!
//! Estes números e regras foram validados no hardware (M1, 2026-11-04).
//! Qualquer alteração no driver que viole estes contratos deve falhar o CI
//! *antes* de ir para o cartão.

/// Índice do anel default no GENET v5 (U-Boot / Linux bcmgenet).
pub const DEFAULT_Q: u32 = 0x10;

/// Shift do enable de ring no `DMA_CTRL` (não no `DMA_RING_CFG`).
pub const DMA_RING_BUF_EN_SHIFT: u32 = 1;

/// Bit correcto em `DMA_RING_CFG` para o anel default.
///
/// Bug histórico: usar `1 << (DEFAULT_Q + SHIFT)` em RING_CFG activava o anel
/// errado → TX stall / timeout (sem beacons `0x88b5`).
pub fn dma_ring_cfg_enable_bit(q: u32) -> u32 {
    1u32 << q
}

/// Bit correcto em `DMA_CTRL` (enable do ring + DMA_EN à parte).
pub fn dma_ctrl_ring_enable_bit(q: u32) -> u32 {
    1u32 << (q + DMA_RING_BUF_EN_SHIFT)
}

/// O bit de RING_CFG **nunca** deve coincidir com o de CTRL para o mesmo q.
pub fn ring_cfg_must_differ_from_ctrl(q: u32) -> bool {
    dma_ring_cfg_enable_bit(q) != dma_ctrl_ring_enable_bit(q)
}

/// EtherType do beacon M1.
pub const AIOS_BOOT_ETHERTYPE: u16 = 0x88b5;

/// Prefixo ASCII do payload do beacon.
pub const AIOS_BOOT_PREFIX: &str = "AIOS-BOOT";

/// md5 do `bcm2711-genetd` M1 validado (beacon-only, login + TX no cabo).
pub const GENETD_M1_MD5: &str = "96ceeaa61d2a13a7df417e977ee4b8f5";

/// md5 do genetd M2 que hangou no HW (NetworkScheme sem IRQ) — não regravar.
pub const GENETD_M2_HANG_MD5: &str = "1af1edf3473969f7c61e388de8153db0";
