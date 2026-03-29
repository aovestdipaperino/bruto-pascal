fn main() -> turbo_vision::core::error::Result<()> {
    bruto_ide::ide::run(Box::new(bruto_pascal_lang::MiniPascal))
}
