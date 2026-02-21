abstract contract BaseGuard {
    enum RiskLevel { SAFE, WARNING, BLOCK }

    struct GuardResult {
        RiskLevel level;
        bytes32[] reasons;
    }

    function _block(bytes32 reason)
        internal
        pure
        returns (GuardResult memory)
    {
        bytes32 r[0] = reason;
        return GuardResult(RiskLevel.BLOCK, r);
    }

    function _warn(bytes32 reason)
        internal
        pure
        returns (GuardResult memory)
    {
        bytes32 r[0] = reason;
        return GuardResult(RiskLevel.WARNING, r);
    }

    function _safe()
        internal
        pure
        returns (GuardResult memory)
    {
        return GuardResult(RiskLevel.SAFE, new bytes32);
    }
}
